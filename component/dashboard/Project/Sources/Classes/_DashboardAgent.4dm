property worker : 4D.SystemWorker
property currentDirectory : 4D.Folder
property state; options : Object
property collector : cs._DashboardCollector
property target; buffer; epoch; diagnostic : Text
property sequence : Real
property closing : Boolean

Class constructor($target : Text; $options : Object; $state : Object)
	This.target:=$target
	This.options:=$options
	This.state:=$state
	This.buffer:=""
	This.diagnostic:=""
	This.epoch:=Generate UUID
	This.sequence:=0
	This.closing:=False

Function launch()
	var $resolved : Object
	var $command; $argument; $previous : Text
	var $value : Variant
	var $adapter : cs._Process
	var CLI_LastErrors : Collection
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
	This.collector:=cs._DashboardCollector.new()
	This.send("hello"; New object("info"; This.collector.info))
	This.send("snapshot"; This.collector.snapshot())

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
	This.sequence+=1
	$payload.protocol:=1
	$payload.kind:=$kind
	$payload.epoch:=This.epoch
	$payload.seq:=This.sequence
	$payload.sampledAt:=String(Current date; ISO date GMT; Current time)
	This.worker.postMessage(JSON Stringify($payload)+Char(10))

Function onData($worker : 4D.SystemWorker; $event : Object)
	var $position : Integer
	var $line; $previous : Text
	var $message : Variant
	var CLI_LastErrors : Collection
	If (This.closing)
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
		Case of
			: ($message.kind="ready")
				If (Value type($message.url)#Is text)
					This.fail("Missing dashboard URL")
					This.stop()
					return
				End if
				Use (This.state)
					This.state.url:=$message.url
					This.state.status:="running"
				End use
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
				This.send("snapshot"; This.collector.snapshot())
				This.send("result"; New object("id"; $message.id; "ok"; True))
				Use (This.state)
					This.state.samples+=1
				End use
			Else
				This.fail("Unknown dashboard message")
				This.stop()
				return
		End case
		$position:=Position(Char(10); This.buffer; *)
	End while

Function onDataError($worker : 4D.SystemWorker; $event : Object)
	This.diagnostic:=Substring(This.diagnostic+$event.data; 1; 4096)
	If (Length(This.diagnostic)>0)
		This.fail(This.diagnostic)
	End if

Function onError($worker : 4D.SystemWorker; $event : Object)
	This.fail("Dashboard system worker failed")

Function onTerminate($worker : 4D.SystemWorker; $event : Object)
	If (Not(This.closing))
		This.fail("Dashboard exited unexpectedly: "+String($worker.exitCode))
	End if
	This.worker:=Null
	This.collector:=Null
	This.buffer:=""
	This.diagnostic:=""
	var Dashboard_Agent : cs._DashboardAgent
	Dashboard_Agent:=Null

Function fail($message : Text)
	Use (This.state)
		This.state.status:="failed"
		This.state.error:=$message
	End use

Function stop()
	var $worker : 4D.SystemWorker
	This.closing:=True
	If (This.worker#Null)
		$worker:=This.worker
		$worker.closeInput()
		$worker.wait(2)
		If (Not($worker.terminated))
			$worker.terminate()
			$worker.wait(1)
		End if
	End if
	Use (This.state)
		If (This.state.status#"failed")
			This.state.status:="stopped"
		End if
	End use
	This.buffer:=""
	This.collector:=Null
