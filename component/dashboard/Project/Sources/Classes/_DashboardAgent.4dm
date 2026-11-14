property worker : 4D.SystemWorker
property currentDirectory : 4D.Folder
property state; options; event; monitor : Object
property target; buffer; epoch; diagnostic; callbackWorker; transportError : Text
property sequence : Real
property closing; finalized : Boolean

Class constructor($target : Text; $options : Object; $state : Object; $event : Object; $monitor : Object)
	This.target:=$target
	This.options:=$options
	This.state:=$state
	This.event:=$event
	This.monitor:=$monitor
	This.buffer:=""
	This.diagnostic:=""
	This.transportError:=""
	This.epoch:=$state.epoch
	This.callbackWorker:="Dashboard.callbacks."+This.epoch
	This.sequence:=0
	This.closing:=False
	This.finalized:=False

Function launch()
	var $resolved : Object
	var $command; $argument; $previous : Text
	var $value : Variant
	var $adapter : cs._Process
	var CLI_LastErrors : Collection
	This.notify("starting")
	CALL WORKER("Dashboard.startup."+This.epoch; "_DashboardStop"; This.state; True)
	$resolved:=cs._CLI.new("dashboard"; This.target).resolve()
	If (Not($resolved.ok))
		This.fail($resolved.error.code)
		return
	End if
	$adapter:=cs._Process.new()
	$command:=$adapter.quote($resolved.file.path)+" serve"
	For each ($argument; New collection("listen"; "tls-cert"; "tls-key"))
		$value:=This.options[$argument]
		If (Value type($value)#Is undefined)
			If (Value type($value)#Is text)
				This.fail("CLI options must be Text")
				return
			End if
			If ((Length($value)>4096) | (Position(Char(0); $value; *)>0))
				This.fail("Invalid CLI option length or NUL")
				return
			End if
			$command+=" --"+$argument+" "+$adapter.quote($value)
		End if
	End for each
	If (Value type(This.options.allowLAN)#Is undefined)
		If (Value type(This.options.allowLAN)#Is boolean)
			This.fail("allowLAN must be Boolean")
			return
		End if
		If (This.options.allowLAN)
			$command+=" --allow-lan"
		End if
	End if
	For each ($argument; OB Keys(This.options))
		If (New collection("listen"; "tls-cert"; "tls-key"; "allowLAN").indexOf($argument)<0)
			This.fail("Unknown dashboard option")
			return
		End if
	End for each
	This.currentDirectory:=$resolved.file.parent
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	This.worker:=4D.SystemWorker.new($command; This)
	ON ERR CALL($previous; ek local)
	If ((This.worker=Null) | (CLI_LastErrors#Null))
		CLI_LastErrors:=Null
		This.fail("Could not launch the bundled dashboard")
		return
	End if
	This.sample(True)

Function sample($initial : Boolean)
	var $signal : 4D.Signal
	var $payload : Object
	$signal:=New signal
	CALL WORKER(This.callbackWorker; "_DashboardSample"; "sample"; This.state; This.event; This.monitor; $signal; "")
	If (Not($signal.wait(5)))
		This.fail("Dashboard collection timed out")
		return
	End if
	If (Value type($signal.error)=Is text)
		This.fail("Dashboard collection failed: "+$signal.error)
		return
	End if
	If (This.closing | This.state.finished)
		return
	End if
	$payload:=JSON Parse($signal.payload)
	If ($initial)
		This.send("hello"; New object("info"; $payload.info))
	End if
	This.send("snapshot"; $payload.snapshot)

Function notify($kind : Text)
	var $status : Object
	$status:=New object("kind"; $kind; "status"; This.state.status; "url"; This.state.url; "error"; This.state.error; "samples"; This.state.samples; "epoch"; This.state.epoch; "port"; This.state.port; "finished"; This.state.finished)
	CALL WORKER(This.callbackWorker; "_DashboardSample"; "notify"; This.state; This.event; This.monitor; Null; $kind; $status)

Function get dataType()->$value : Text
	$value:="text"

Function get encoding()->$value : Text
	$value:="UTF-8"

Function get hideWindow()->$value : Boolean
	$value:=True

Function send($kind : Text; $payload : Object)
	If (This.closing)
		return
	End if
	If (This.state.stopRequested)
		This.stop()
		return
	End if
	This.sequence+=1
	$payload.protocol:=1
	$payload.kind:=$kind
	$payload.epoch:=This.epoch
	$payload.seq:=This.sequence
	$payload.sampledAt:=String(Current date; ISO date GMT; Current time)
	Try(This.worker.postMessage(JSON Stringify($payload)+Char(10)))
	If (Last errors#Null)
		This.transportError:="Dashboard stdin write failed: "+JSON Stringify(Last errors)
		This.fail(This.transportError)
	End if

Function onData($worker : 4D.SystemWorker; $event : Object)
	var $position : Integer
	var $line; $previous : Text
	var $message : Variant
	var CLI_LastErrors : Collection
	If (This.closing)
		return
	End if
	If (This.state.stopRequested)
		This.stop()
		return
	End if
	This.buffer+=$event.data
	If (Length(This.buffer)>262144)
		This.fail("Dashboard output exceeded the frame limit")
		This.stop()
		return
	End if
	$position:=Position(Char(10); This.buffer; *)
	While ($position>0)
		$line:=Substring(This.buffer; 1; $position-1)
		This.buffer:=Substring(This.buffer; $position+1)
		$previous:=Method called on error(ek local)
		CLI_LastErrors:=Null
		ON ERR CALL("_CaptureError"; ek local)
		$message:=JSON Parse($line)
		ON ERR CALL($previous; ek local)
		If ((CLI_LastErrors#Null) | (Value type($message)#Is object))
			This.fail("Invalid dashboard output")
			This.stop()
			return
		End if
		If ((Value type($message.protocol)#Is real) & (Value type($message.protocol)#Is longint))
			This.fail("Invalid dashboard protocol type")
			This.stop()
			return
		End if
		If ($message.protocol#1)
			This.fail("Unsupported dashboard protocol")
			This.stop()
			return
		End if
		If (Value type($message.kind)#Is text)
			This.fail("Invalid dashboard message kind")
			return
		End if
		Case of
			: ($message.kind="ready")
				If (Value type($message.url)#Is text)
					This.fail("Missing dashboard URL")
					This.stop()
					return
				End if
				If (Not(Match regex("^https?://(\\[[0-9A-Fa-f:]+\\]|[0-9.]+):[0-9]+/#token=[0-9a-f]{64}$"; $message.url)))
					This.fail("Invalid dashboard listening URL")
					return
				End if
				var $port; $colon; $index : Integer
				var $origin : Text
				var $manager : cs.workers.worker
				$origin:=Substring($message.url; 1; Position("/#token="; $message.url; *)-1)
				For ($index; 1; Length($origin))
					If ($origin[[$index]]=":")
						$colon:=$index
					End if
				End for
				$port:=Num(Substring($origin; $colon+1))
				If (($port<1) | ($port>65535))
					This.fail("Invalid dashboard listening port")
					return
				End if
				$manager:=cs.workers.worker.new(cs._DashboardServer)
				If (Not($manager.start($port; New object("agent"; This))))
					This.fail("Dashboard instance registration failed: "+JSON Stringify($manager.errors))
					return
				End if
				Use (This.state)
					This.state.port:=$port
					This.state.url:=$message.url
					This.state.status:="running"
				End use
				_DashboardWorker("adopted"; ""; New object; This.state; New object; New object)
				This.notify("running")
			: ($message.kind="request")
				If ((Value type($message.id)#Is text) | (Value type($message.epoch)#Is text) | (Value type($message.action)#Is text))
					This.fail("Invalid dashboard request")
					This.stop()
					return
				End if
				If (Not(Match regex("^[a-f0-9]{64}$"; $message.id)))
					This.fail("Invalid dashboard correlation ID")
					This.stop()
					return
				End if
				If (($message.epoch#This.epoch) | ($message.action#"refresh"))
					This.fail("Unrecognized dashboard request")
					This.stop()
					return
				End if
				This.sample(False)
				If (This.closing | (This.state.status="failed"))
					return
				End if
				This.send("result"; New object("id"; $message.id; "ok"; True))
				Use (This.state)
					This.state.samples+=1
				End use
				This.notify("sample")
			Else
				This.fail("Unknown dashboard message")
				This.stop()
				return
		End case
		$position:=Position(Char(10); This.buffer; *)
	End while

Function onDataError($worker : 4D.SystemWorker; $event : Object)
	This.diagnostic:=Substring(This.diagnostic+$event.data; 1; 4096)

Function onError($worker : 4D.SystemWorker; $event : Object)
	If (Length(This.diagnostic)>0)
		This.fail(This.diagnostic)
	Else
		This.fail("Dashboard system worker failed")
	End if

Function onTerminate($worker : 4D.SystemWorker; $event : Object)
	If ((This.transportError#"") & (This.state.error=This.transportError) & (This.diagnostic#""))
		Use (This.state)
			This.state.error:=This.diagnostic
		End use
	End if
	If (Not(This.closing) & (This.state.status#"failed"))
		If (Length(This.diagnostic)>0)
			This.fail(This.diagnostic)
		Else
			This.fail("Dashboard exited unexpectedly: "+String($worker.exitCode))
		End if
	End if
	This.finish()

Function fail($message : Text)
	If (This.state.finished)
		return
	End if
	Use (This.state)
		This.state.status:="failed"
		This.state.error:=$message
		This.state.url:=""
	End use
	This.closing:=True
	If (This.worker#Null)
		If (Not(This.state.stopRequested))
			Use (This.state)
				This.state.stopRequested:=True
			End use
			CALL WORKER("Dashboard.stop."+This.epoch; "_DashboardStop"; This.state)
		End if
		This.worker.closeInput()
	Else
		This.finish()
	End if

Function stop()
	This.closing:=True
	If (This.worker#Null)
		This.worker.closeInput()
	Else
		This.finish()
	End if

Function force()
	This.closing:=True
	If (This.worker#Null)
		This.worker.terminate()
	Else
		This.finish()
	End if

Function finish()
	If (This.finalized)
		return
	End if
	This.finalized:=True
	If (Not(This.state.forceDrain))
		_DashboardWorker("release"; ""; New object; This.state; New object; New object)
	End if
	Use (This.state)
		If (This.state.status#"failed")
			This.state.status:="stopped"
		End if
		This.state.url:=""
		This.state.finished:=This.state.finished | Not(This.state.forceDrain)
	End use
	This.worker:=Null
	This.buffer:=""
	This.options:=Null
	If (Not(This.state.forceDrain))
		This.notify(This.state.status)
	End if
	This.event:=Null
	This.monitor:=Null
