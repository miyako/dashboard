//%attributes = {"invisible":true}
// Test-only (macOS): the PID of the process listening on $port, via lsof; 0 when none.
#DECLARE($port : Integer)->$pid : Integer
var $worker : 4D.SystemWorker
$worker:=4D.SystemWorker.new("/usr/sbin/lsof -nP -t -iTCP:"+String($port)+" -sTCP:LISTEN")
$worker.wait(5)
$pid:=Num(Split string(String($worker.response); Char(10); sk ignore empty strings).first())
