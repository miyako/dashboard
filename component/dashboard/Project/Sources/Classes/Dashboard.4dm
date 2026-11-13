property _cli : cs._CLI

Class constructor($target : Text)
	This._cli:=cs._CLI.new("dashboard"; $target)

Function inspect($text : Text)->$result : Object
	$result:=This._decode(This._cli.execute(New collection("inspect"; "--text"; $text)); "text")

Function collect()->$result : Object
	If (Num(Substring(Application version; 1; 2))<21)
		return New object("ok"; False; "error"; New object("code"; "unsupported_host"; "message"; "4D 21 LTS or later is required"))
	End if
	$result:=New object("ok"; True; "value"; cs._DashboardCollector.new().snapshot())

Function start($options : Object)->$state : Object
	$state:=New shared object("status"; "starting"; "url"; ""; "error"; ""; "samples"; 0)
	If (Num(Substring(Application version; 1; 2))<21)
		Use ($state)
			$state.status:="failed"
			$state.error:="4D 21 LTS or later is required"
		End use
		return $state
	End if
	If ($options=Null)
		$options:=New object
	End if
	CALL WORKER("Dashboard.monitor"; "_DashboardWorker"; "start"; This._cli.target; $options; $state)

Function stop()
	CALL WORKER("Dashboard.monitor"; "_DashboardWorker"; "stop"; ""; New object; New shared object)

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
