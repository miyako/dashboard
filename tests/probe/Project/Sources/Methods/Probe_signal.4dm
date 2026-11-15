//%attributes = {"invisible":true}
// Probe helper: starts a child process, sends it a signal (or calls terminate when $signal is ""),
// and returns what 4D.SystemWorker then reports. Used to classify CLI exits for restarts.
#DECLARE($signal : Text; $field : Text)->$value : Variant
var $worker; $kill : 4D.SystemWorker
$worker:=4D.SystemWorker.new("/bin/sleep 30")
If ($signal="")
	$worker.terminate()
Else
	$kill:=4D.SystemWorker.new("/bin/kill "+$signal+" "+String($worker.pid))
	$kill.wait(5)
End if
$worker.wait(5)
$value:=$worker[$field]
