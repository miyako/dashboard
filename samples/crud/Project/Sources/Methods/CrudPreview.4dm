//%attributes = {"invisible":true}
var $ignored; $deadline : Integer
var $parameter; $phase : Text
var $request; $service; $report; $baseline; $measure : Object
var $monitor : cs.Dashboard.Dashboard
var $workload : cs.CrudWorkload
var $requestFile; $statusFile; $stopFile : 4D.File
var CRUD_StatusFile : 4D.File
var CRUD_Monitor : cs.Dashboard.Dashboard
var CRUD_PreviousHandler : Text
$ignored:=Get database parameter(User param value; $parameter)
If (Is Windows)
	$requestFile:=File($parameter; fk platform path)
Else
	$requestFile:=File($parameter; fk posix path)
End if
$request:=JSON Parse($requestFile.getText())
$statusFile:=$requestFile.parent.file("preview-status.json")
$stopFile:=$requestFile.parent.file("stop")
CRUD_StatusFile:=$statusFile
CRUD_PreviousHandler:=Method called on error(ek local)
ON ERR CALL("Crud_error"; ek local)
$monitor:=cs.Dashboard.Dashboard.new($request.target)
CRUD_Monitor:=$monitor
$workload:=cs.CrudWorkload.new()
$baseline:=Database measures(New object("withHistory"; False))
$service:=$monitor.start(New object)
$deadline:=Milliseconds+($request.seconds*1000)
$report:=New object("success"; False; "finished"; False; "phase"; "starting"; "counts"; $workload.counts; "baseline"; $baseline; "samples"; New collection; "hostCompiled"; Is compiled mode(*))
While (($service.status#"failed") & (Milliseconds<$deadline) & Not($stopFile.exists) & ($workload.error=""))
	$phase:=$workload.step()
	$measure:=Database measures(New object("withHistory"; False))
	$report.phase:=$phase
	$report.rows:=ds.CrudRecords.all().length
	$report.error:=$workload.error
	$report.samples.push(New object("at"; String(Current date; ISO date GMT; Current time); "phase"; $phase; "measures"; $measure))
	If ($report.samples.length>60)
		$report.samples.shift()
	End if
	$report.service:=New object("status"; $service.status; "url"; $service.url; "error"; $service.error; "samples"; $service.samples)
	$statusFile.setText(JSON Stringify($report))
	DELAY PROCESS(Current process; 120)
End while
$workload.finish()
$report.error:=$workload.error
$report.rows:=ds.CrudRecords.all().length
$report.final:=Database measures(New object("withHistory"; False))
$report.success:=($workload.error="") & ($service.status="running") & ($workload.counts.cycles>0) & ($report.rows=0)
$monitor.stop()
$deadline:=Milliseconds+5000
While (($service.status#"stopped") & ($service.status#"failed") & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.success:=$report.success & ($service.status="stopped")
$report.service:=New object("status"; $service.status; "url"; $service.url; "error"; $service.error; "samples"; $service.samples)
$report.finished:=True
$statusFile.setText(JSON Stringify($report))
ON ERR CALL(CRUD_PreviousHandler; ek local)
QUIT 4D
