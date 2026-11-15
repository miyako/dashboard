//%attributes = {"invisible":true}
// Test-only (macOS): sends a signal (for example "-9" or "-STOP") to a PID.
#DECLARE($signal : Text; $pid : Integer)
var $worker : 4D.SystemWorker
If ($pid>0)
	$worker:=4D.SystemWorker.new("/bin/kill "+$signal+" "+String($pid))
	$worker.wait(5)
End if
