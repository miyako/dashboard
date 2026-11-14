property _cli : cs._CLI
property state : Object

Class constructor($target : Text)
	This._cli:=cs._CLI.new("dashboard"; $target)

Function inspect($text : Text)->$result : Object
	$result:=This._decode(This._cli.execute(New collection("inspect"; "--text"; $text)); "text")

Function collect()->$result : Object
	If (Num(Substring(Application version; 1; 2))<21)
		return New object("ok"; False; "error"; New object("code"; "unsupported_host"; "message"; "4D 21 LTS or later is required"))
	End if
	$result:=New object("ok"; True; "value"; cs._DashboardCollector.new().snapshot())

Function start($options : Object; $event : Object)->$state : Object
	$state:=New shared object("status"; "starting"; "url"; ""; "operatorUrl"; ""; "error"; ""; "samples"; 0; "epoch"; Generate UUID; "port"; 0; "stopRequested"; False; "finished"; False; "callbackError"; ""; "cleanupError"; ""; "forceDrain"; False)
	If (Num(Substring(Application version; 1; 2))<21)
		Use ($state)
			$state.status:="failed"
			$state.error:="4D 21 LTS or later is required"
			$state.finished:=True
		End use
		return $state
	End if
	If ($options=Null)
		$options:=New object
	End if
	If ($event=Null)
		$event:=New object
	End if
	If (Value type($event.onStatus)#Is undefined)
		If (Value type($event.onStatus)#Is object)
			Use ($state)
				$state.status:="failed"
				$state.error:="onStatus must be a Formula or function"
				$state.finished:=True
			End use
			return $state
		End if
		If (Not(OB Instance of($event.onStatus; 4D.Function)))
			Use ($state)
				$state.status:="failed"
				$state.error:="onStatus must be a Formula or function"
				$state.finished:=True
			End use
			return $state
		End if
	End if
	If (This.state#Null)
		If (Not(This.state.finished))
			Use ($state)
				$state.status:="failed"
				$state.error:="This dashboard controller already owns an active instance"
				$state.finished:=True
			End use
			var $rejected : cs.Dashboard
			$rejected:=cs.Dashboard.new(This._cli.target)
			$rejected.state:=$state
			CALL WORKER("Dashboard.callbacks."+$state.epoch; "_DashboardSample"; "reject"; $state; $event; $rejected; Null; "failed")
			return $state
		End if
	End if
	This.state:=$state
	CALL WORKER(".workers"; "_DashboardWorker"; "start"; This._cli.target; $options; $state; $event; This)

Function stop()
	If (This.state#Null)
		If (Not(This.state.finished))
			CALL WORKER(".workers"; "_DashboardWorker"; "stop"; ""; New object; This.state; New object; This)
		End if
	End if

Function terminate()->$terminated : Boolean
	// Ends this instance's active dashboard whichever facade started it, and waits for cleanup.
	var $signal : 4D.Signal
	var $deadline : Real
	If (Current process name=".workers")
		return False  // the shutdown runs on .workers, which cannot wait for itself
	End if
	$deadline:=Milliseconds+20000
	$signal:=New signal
	CALL WORKER(".workers"; "_DashboardWorker"; "terminate"; ""; New object; New object; New object; New object; $signal)
	If (Not($signal.wait(5)))
		return False
	End if
	Repeat
		$signal:=New signal
		CALL WORKER(".workers"; "_DashboardWorker"; "active"; ""; New object; New object; New object; New object; $signal)
		If (Not($signal.wait(5)))
			return False
		End if
		If (Not($signal.active))
			return True
		End if
		DELAY PROCESS(Current process; 6)
	Until (Milliseconds>$deadline)
	$terminated:=False

Function version()->$result : Object
	$result:=This._decode(This._cli.execute(New collection("--version")); "version")

Function _decode($result : Object; $field : Text)->$decoded : Object
	var $payload : Variant
	var $previous : Text
	var $parseErrors : Collection
	var CLI_LastErrors : Collection
	If (Not($result.ok))
		return $result
	End if
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	$payload:=JSON Parse($result.stdout)
	ON ERR CALL($previous; ek local)
	$parseErrors:=CLI_LastErrors
	CLI_LastErrors:=Null
	If (($parseErrors#Null) | (Value type($payload)#Is object))
		$result.ok:=False
		$result.error:=New object("code"; "invalid_protocol"; "message"; "CLI response must be a JSON object"; "details"; $parseErrors)
		return $result
	End if
	If ((Value type($payload.protocol)#Is real) & (Value type($payload.protocol)#Is longint))
		$result.ok:=False
		$result.error:=New object("code"; "invalid_protocol"; "message"; "Unsupported CLI protocol version")
		return $result
	End if
	If (($payload.protocol#1) | (Value type($payload[$field])#Is text))
		$result.ok:=False
		$result.error:=New object("code"; "invalid_protocol"; "message"; "Unsupported CLI protocol version")
		return $result
	End if
	$result.value:=$payload
	$decoded:=$result
