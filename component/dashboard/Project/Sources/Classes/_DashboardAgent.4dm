property worker : 4D.SystemWorker
property currentDirectory : 4D.Folder
property state; options; event; monitor : Object
property operator : cs._DashboardOperator
property authorize : 4D.Function
property busy; run : Integer
property target; buffer; epoch; baseEpoch; diagnostic; callbackWorker; transportError; command : Text
property sequence; lastFrameAt; restartAt; hungAt : Real
property closing; finalized; ready; hung; restartPending; exclusiveRunning : Boolean
property restartPolicy : Object
property restartTimes; logFamilies : Collection

Class constructor($target : Text; $options : Object; $state : Object; $event : Object; $monitor : Object)
	This.target:=$target
	This.options:=$options
	This.state:=$state
	This.event:=$event
	This.monitor:=$monitor
	This.buffer:=""
	This.diagnostic:=""
	This.transportError:=""
	// Instance identity (state.epoch) never changes; the protocol epoch gets ".r<n>" for each restarted CLI run.
	This.baseEpoch:=$state.epoch
	This.epoch:=$state.epoch
	This.run:=0
	This.callbackWorker:="Dashboard.callbacks."+This.baseEpoch
	This.sequence:=0
	This.busy:=0
	This.closing:=False
	This.finalized:=False
	This.ready:=False
	This.hung:=False
	This.restartPending:=False
	This.exclusiveRunning:=False
	This.restartTimes:=New collection
	This.command:=""

Function launch()
	var $resolved : Object
	var $command; $argument; $previous : Text
	var $value : Variant
	var $adapter : cs._Process
	var CLI_LastErrors : Collection
	This.notify("starting")
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
	If (Value type(This.options.operator)#Is undefined)
		// Explicit host opt-in only; a separate operator token is minted by the CLI.
		var $operator : Object
		$operator:=cs._DashboardOperator.new().validate(This.options.operator)
		If (Not($operator.ok))
			This.fail($operator.error)
			return
		End if
		This.operator:=cs._DashboardOperator.new($operator.actions; This.epoch; cs._DashboardOperator.new().defaultFolder())
		If (Value type($operator.authorize)=Is object)
			This.authorize:=$operator.authorize
		End if
		$command+=" --operator-actions "+$adapter.quote($operator.actions.join(","))
	End if
	If (Value type(This.options.logs)#Is undefined)
		// Log browsing (docs/log-browsing-design.md): the CLI reads the host Logs folder; 4D authorizes and audits.
		var $logs : Object
		var $logsFolder : 4D.Folder
		$logs:=cs._DashboardOperator.new().validateLogs(This.options.logs; This.operator#Null)
		If (Not($logs.ok))
			This.fail($logs.error)
			return
		End if
		This.logFamilies:=$logs.families
		$logsFolder:=Folder(fk logs folder; *)
		If (Not($logsFolder.exists))
			$logsFolder.create()
		End if
		// Folder.path is a filesystem alias ("/LOGS/") here, not a real path: convert the platform path instead.
		$command+=" --logs-root "+$adapter.quote(Choose(Is Windows; $logsFolder.platformPath; Convert path system to POSIX($logsFolder.platformPath)))+" --log-families "+$adapter.quote(This.logFamilies.join(","))
	End if
	var $policy : Object
	$policy:=This.restartPolicyFrom(This.options.restart)
	If (Not($policy.ok))
		This.fail($policy.error)
		return
	End if
	This.restartPolicy:=$policy.policy
	For each ($argument; OB Keys(This.options))
		If (New collection("listen"; "tls-cert"; "tls-key"; "allowLAN"; "operator"; "restart"; "logs").indexOf($argument)<0)
			This.fail("Unknown dashboard option")
			return
		End if
	End for each
	This.currentDirectory:=$resolved.file.parent
	This.command:=$command
	// One timer per instance drives restart delays, liveness and forced stops; see docs/restart-strategy.md.
	CALL WORKER("Dashboard.watch."+This.baseEpoch; "_DashboardWatch"; This.state)
	This.spawn()

Function spawn()
	// Starts one CLI run with the validated command; used for the first run and every restart.
	var $previous : Text
	var CLI_LastErrors : Collection
	CALL WORKER("Dashboard.startup."+This.epoch; "_DashboardStop"; This.state; True)
	This.ready:=False
	This.hung:=False
	This.lastFrameAt:=Milliseconds
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	This.worker:=4D.SystemWorker.new(This.command; This)
	ON ERR CALL($previous; ek local)
	If ((This.worker=Null) | (CLI_LastErrors#Null))
		CLI_LastErrors:=Null
		This.fail("Could not launch the bundled dashboard")
		return
	End if
	This.sample(True)

Function restartPolicyFrom($value : Variant)->$result : Object
	// Pure: validates the optional restart option; defaults per docs/restart-strategy.md.
	var $key : Text
	var $limits; $policy : Object
	$policy:=New object("max"; 5; "windowSeconds"; 600; "initialDelayMs"; 1000; "livenessSeconds"; 45)
	$result:=New object("ok"; True; "policy"; $policy)
	If (Value type($value)=Is undefined)
		return
	End if
	$result:=New object("ok"; False; "error"; "restart must be an object of max, windowSeconds, initialDelayMs and livenessSeconds")
	If (Value type($value)#Is object)
		return
	End if
	$limits:=New object("max"; New collection(0; 10); "windowSeconds"; New collection(60; 3600); "initialDelayMs"; New collection(250; 10000); "livenessSeconds"; New collection(15; 300))
	For each ($key; OB Keys($value))
		If (Value type($limits[$key])#Is collection)
			return
		End if
		If ((Value type($value[$key])#Is real) & (Value type($value[$key])#Is longint))
			return
		End if
		If ((Int($value[$key])#$value[$key]) | ($value[$key]<$limits[$key][0]) | ($value[$key]>$limits[$key][1]))
			$result.error:="restart."+$key+" must be an integer from "+String($limits[$key][0])+" to "+String($limits[$key][1])
			return
		End if
		$policy[$key]:=$value[$key]
	End for each
	$result:=New object("ok"; True; "policy"; $policy)

Function restartReason($exitCode : Variant; $ready : Boolean; $hung : Boolean)->$reason : Text
	// Pure classification of an exit we did not request; "" means do not restart.
	$reason:=""
	Case of
		: ($hung)
			$reason:="unresponsive"
		: (Not($ready))
			// Startup failures are configuration problems: report, never loop.
		: ((Value type($exitCode)#Is real) & (Value type($exitCode)#Is longint))
			// 4D reports no exit code when the process was killed by a signal.
			$reason:="crashed"
		: ($exitCode=2)
			// The CLI reported its own error on stderr (protocol, backpressure, listener).
		Else
			$reason:="exited"
	End case

Function restartDelay($count : Integer; $initialMs : Integer)->$delay : Integer
	// Pure: initial × 2^count, capped at 60 s.
	var $index : Integer
	$delay:=$initialMs
	For ($index; 1; $count)
		$delay:=$delay*2
		If ($delay>=60000)
			$delay:=60000
			return
		End if
	End for

Function scheduleRestart($reason : Text)->$result : Object
	var $now : Real
	var $recent : Collection
	var $delay : Integer
	var $oldEpoch : Text
	$result:=New object("scheduled"; False; "limited"; False)
	If (This.restartPolicy=Null)
		return
	End if
	If (This.restartPolicy.max=0)
		return
	End if
	$now:=Milliseconds
	var $time : Real
	$recent:=New collection
	For each ($time; This.restartTimes)
		If ($time>($now-(This.restartPolicy.windowSeconds*1000)))
			$recent.push($time)
		End if
	End for each
	This.restartTimes:=$recent
	If (This.restartTimes.length>=This.restartPolicy.max)
		$result.limited:=True
		return
	End if
	$delay:=This.restartDelay(This.restartTimes.length; This.restartPolicy.initialDelayMs)
	This.restartTimes.push($now)
	$oldEpoch:=This.epoch
	// Release this run's port registration; a queued executor action finishes and is audited as orphaned.
	If (This.state.port>0)
		cs.workers.worker.new(cs._DashboardServer).terminate(This.state.port)
	End if
	If (This.operator#Null)
		CALL WORKER("Dashboard.admin."+$oldEpoch; "_DashboardAdmin"; "stop")
	End if
	This.worker:=Null
	This.buffer:=""
	This.sequence:=0
	This.busy:=0
	This.ready:=False
	This.hung:=False
	This.exclusiveRunning:=False
	This.diagnostic:=""
	This.transportError:=""
	This.restartPending:=True
	This.restartAt:=$now+$delay
	Use (This.state)
		This.state.status:="restarting"
		This.state.url:=""
		This.state.operatorUrl:=""
		This.state.port:=0
		This.state.restarts:=This.state.restarts+1
		This.state.lastRestartReason:=$reason
	End use
	This.notify("restarting"; New object("reason"; $reason; "attempt"; This.restartTimes.length; "delayMs"; $delay))
	$result.scheduled:=True

Function relaunch()
	This.restartPending:=False
	If (This.state.stopRequested | This.closing)
		This.closing:=True
		This.finish()
		return
	End if
	This.run+=1
	This.epoch:=This.baseEpoch+".r"+String(This.run)
	If (This.operator#Null)
		This.operator.epoch:=This.epoch
	End if
	This.spawn()

Function tick()
	// Once a second from Dashboard.watch.<epoch>: restart delay, forced stop of a hung CLI, liveness.
	If (This.finalized)
		return
	End if
	If (This.restartPending)
		If (This.state.stopRequested)
			This.restartPending:=False
			This.closing:=True
			This.finish()
			return
		End if
		If (Milliseconds>=This.restartAt)
			This.relaunch()
		End if
		return
	End if
	If (This.worker=Null)
		return
	End if
	If (This.hung)
		If ((Milliseconds-This.hungAt)>3500)
			This.worker.terminate()
		End if
		return
	End if
	If (This.ready & Not(This.closing) & Not(This.exclusiveRunning) & (This.restartPolicy#Null))
		If ((Milliseconds-This.lastFrameAt)>(This.restartPolicy.livenessSeconds*1000))
			// Controlled stop: close stdin, force after 3.5 s, then onTerminate restarts it.
			This.hung:=True
			This.hungAt:=Milliseconds
			This.worker.closeInput()
		End if
	End if

Function sample($initial : Boolean)->$ok : Boolean
	var $signal : 4D.Signal
	var $payload : Object
	$ok:=False
	$signal:=New signal
	CALL WORKER(This.callbackWorker; "_DashboardSample"; "sample"; This.state; This.event; This.monitor; $signal; "")
	If (Not($signal.wait(5)))
		// One slow sample is not fatal: the refresh is answered collector_busy. Six in a row (about 30 s) are.
		// Mark it abandoned so the queued request is skipped instead of collecting late and piling up.
		Use ($signal)
			$signal.abandoned:=True
		End use
		This.busy+=1
		If ($initial | (This.busy>=6))
			This.fail("Dashboard collection timed out")
		End if
		return
	End if
	This.busy:=0
	If (Value type($signal.error)=Is text)
		This.fail("Dashboard collection failed: "+$signal.error)
		return
	End if
	If (This.closing | This.state.finished)
		return
	End if
	$payload:=JSON Parse($signal.payload)
	$ok:=True
	If ($initial)
		var $hello : Object
		$hello:=New object("info"; $payload.info)
		If (This.operator#Null)
			$hello.operator:=New object("version"; 1; "actions"; This.operator.actions.copy())
		End if
		If (This.logFamilies#Null)
			$hello.logs:=New object("version"; 1; "families"; This.logFamilies.copy())
		End if
		This.send("hello"; $hello)
	End if
	This.send("snapshot"; $payload.snapshot)

Function notify($kind : Text; $extra : Object)
	var $status : Object
	var $key : Text
	$status:=New object("kind"; $kind; "status"; This.state.status; "url"; This.state.url; "operatorUrl"; This.state.operatorUrl; "error"; This.state.error; "samples"; This.state.samples; "epoch"; This.state.epoch; "port"; This.state.port; "finished"; This.state.finished; "restarts"; Num(This.state.restarts))
	If ($extra#Null)
		For each ($key; OB Keys($extra))
			$status[$key]:=$extra[$key]
		End for each
	End if
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
	var $begun : Object
	var CLI_LastErrors : Collection
	If (This.closing | This.hung)
		return
	End if
	If (This.state.stopRequested)
		This.stop()
		return
	End if
	This.lastFrameAt:=Milliseconds
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
				If (Not(This._operatorReady($message)))
					return
				End if
				If (This.logFamilies=Null)
					If (Value type($message.logs)#Is undefined)
						This.fail("Unexpected dashboard log negotiation")
						return
					End if
				Else
					If (Value type($message.logs)#Is object)
						This.fail("Missing dashboard log negotiation")
						return
					End if
					If ((Num($message.logs.version)#1) | (JSON Stringify($message.logs.families)#JSON Stringify(This.logFamilies)))
						This.fail("Dashboard log families differ from the request")
						return
					End if
				End if
				$manager:=cs.workers.worker.new(cs._DashboardServer)
				If (Not($manager.start($port; New object("agent"; This))))
					This.fail("Dashboard instance registration failed: "+JSON Stringify($manager.errors))
					return
				End if
				Use (This.state)
					This.state.port:=$port
					This.state.url:=$message.url
					If (This.operator#Null)
						This.state.operatorUrl:=$message.operatorUrl
					End if
					This.state.status:="running"
				End use
				This.ready:=True
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
				If (Not(This.sample(False)))
					If (This.closing | (This.state.status="failed"))
						return
					End if
					This.send("result"; New object("id"; $message.id; "ok"; False; "error"; "collector_busy"))
					$position:=Position(Char(10); This.buffer; *)
					continue
				End if
				If (This.closing | (This.state.status="failed"))
					return
				End if
				This.send("result"; New object("id"; $message.id; "ok"; True))
				Use (This.state)
					This.state.samples+=1
				End use
				This.notify("sample")
			: ($message.kind="logAccess")
				If ((This.operator=Null) | (This.logFamilies=Null))
					This.fail("Unexpected dashboard log access")
					This.stop()
					return
				End if
				var $logCheck : Object
				$logCheck:=This.operator.checkLogAccess($message; This.logFamilies)
				If (Not($logCheck.ok))
					This.fail($logCheck.error)
					This.stop()
					return
				End if
				// Host code (authorize) never runs on .workers: the executor authorizes, audits and answers.
				CALL WORKER("Dashboard.admin."+This.epoch; "_DashboardAdmin"; "logAccess"; This.epoch; $message; Null; $logCheck.family; ""; This.operator.actions; This.operator.folder.platformPath; This.authorize)
			: ($message.kind="action")
				If (This.operator=Null)
					This.fail("Unexpected dashboard action")
					This.stop()
					return
				End if
				$begun:=This.operator.begin($message)
				If (Not($begun.ok))
					This.fail($begun.error)
					This.stop()
					return
				End if
				This.send("actionState"; $begun.frame)
				If (This.closing | (This.state.status="failed"))
					return
				End if
				If ($begun.frame.state="running")
					// Never execute on .workers: hand off to the cooperative executor and keep serving the pipe.
					If ($begun.entry.exclusive=True)
						// The CLI pauses sampling during exclusive actions: liveness is not checked meanwhile.
						This.exclusiveRunning:=True
					End if
					CALL WORKER("Dashboard.admin."+This.epoch; "_DashboardAdmin"; "run"; This.epoch; $message; $begun.record; $begun.entry; $begun.canonical; This.operator.actions; This.operator.folder.platformPath; This.authorize)
				End if
			Else
				This.fail("Unknown dashboard message")
				This.stop()
				return
		End case
		$position:=Position(Char(10); This.buffer; *)
	End while

Function _operatorReady($message : Object)->$ok : Boolean
	// Both sides must agree on operator mode before the dashboard is adopted.
	$ok:=False
	If (This.operator=Null)
		If ((Value type($message.operator)#Is undefined) | (Value type($message.operatorUrl)#Is undefined))
			This.fail("Unexpected dashboard operator negotiation")
			return
		End if
		return True
	End if
	If ((Value type($message.operator)#Is object) | (Value type($message.operatorUrl)#Is text))
		This.fail("Missing dashboard operator negotiation")
		return
	End if
	If ((Value type($message.operator.version)#Is real) & (Value type($message.operator.version)#Is longint))
		This.fail("Invalid dashboard operator negotiation")
		return
	End if
	If (($message.operator.version#1) | (Value type($message.operator.actions)#Is collection))
		This.fail("Invalid dashboard operator negotiation")
		return
	End if
	If (JSON Stringify($message.operator.actions)#JSON Stringify(This.operator.actions))
		This.fail("Dashboard operator actions differ from the request")
		return
	End if
	If (Not(Match regex("^https?://(\\[[0-9A-Fa-f:]+\\]|[0-9.]+):[0-9]+/#token=[0-9a-f]{64}&operator=[0-9a-f]{64}$"; $message.operatorUrl)))
		This.fail("Invalid dashboard operator URL")
		return
	End if
	If (Position($message.url+"&operator="; $message.operatorUrl; *)#1)
		This.fail("Dashboard operator URL does not match the viewer URL")
		return
	End if
	$ok:=True

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
		var $reason : Text
		var $restart : Object
		$reason:=This.restartReason($worker.exitCode; This.ready; This.hung)
		If (This.state.stopRequested | This.state.forceDrain)
			// A requested stop (including its forced escalation) never restarts.
			$reason:=""
		End if
		If ($reason#"")
			$restart:=This.scheduleRestart($reason)
			If ($restart.scheduled)
				return
			End if
			If ($restart.limited)
				This.fail("Dashboard CLI restart limit reached ("+$reason+")"+Choose(Length(This.diagnostic)>0; ": "+This.diagnostic; ""))
				This.finish()
				return
			End if
		End if
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
		This.state.operatorUrl:=""
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
	If (This.operator#Null)
		// Queued after any running action; a result arriving after this is audited as orphaned.
		CALL WORKER("Dashboard.admin."+This.epoch; "_DashboardAdmin"; "stop")
	End if
	If (Not(This.state.forceDrain))
		_DashboardWorker("release"; ""; New object; This.state; New object; New object)
	End if
	Use (This.state)
		If (This.state.status#"failed")
			This.state.status:="stopped"
		End if
		This.state.url:=""
		This.state.operatorUrl:=""
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
