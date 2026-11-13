//%attributes = {"invisible":true}
#DECLARE($status : Object; $monitor : Object)
var $entry : Object
var $process : Object
var $action : Text
$entry:=New object("kind"; $status.kind; "status"; $status.status; "finished"; $status.finished; "urlCleared"; ($status.url=""); "port"; $status.port; "process"; Current process name; "epoch"; $status.epoch)
$process:=Try(Process info(Current process))
If ($process#Null)
	$entry.preemptive:=$process.preemptive
End if
If ($status.kind="running")
	$entry.portObserved:=($status.portCheck.availability="available")
	$entry.listening:=$status.portCheck.listening
End if
Use (This.log.events)
	This.log.events.push(OB Copy($entry; ck shared; This.log.events))
End use
Use (This.log)
	$action:=This.log.action
End use
Case of
	: (($action="stop") & ($status.kind="sample"))
		$monitor.stop()
	: (($action="restart") & ($status.kind="stopped"))
		Use (This.log)
			This.log.action:="stop"
		End use
		$monitor.start(New object; This)
	: ((($action="error") & ($status.kind="running")) | (($action="error-terminal") & ($status.kind="failed")))
		var $invalid : Object
		$invalid:=JSON Parse("invalid callback JSON")
End case
