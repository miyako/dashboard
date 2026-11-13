//%attributes = {"invisible":true}
var $ignored : Integer
var $parameter : Text
var $request; $direct; $reading : Object
var $requestFile; $settings; $dataFile : 4D.File
var $logs : 4D.Folder
var $collector : cs.Dashboard._DashboardCollector
var $date : Date
var $time : Time
var $number : Integer
var $text : Text
var BACKUP_StatusFile : 4D.File
var BACKUP_Report : Object
var BACKUP_PreviousHandler : Text
$ignored:=Get database parameter(User param value; $parameter)
$requestFile:=File($parameter; fk posix path)
$request:=JSON Parse($requestFile.getText())
BACKUP_StatusFile:=$requestFile.parent.file("backup-scope-status.json")
BACKUP_Report:=New object("success"; False; "finished"; False; "phase"; "safety"; "backupAttempted"; False)
BACKUP_PreviousHandler:=Method called on error(ek local)
ON ERR CALL("BackupProbe_error"; ek local)
$settings:=File(Get 4D file(Current backup settings file); fk platform path)
$dataFile:=File(Data file; fk platform path)
$logs:=Folder(Get 4D folder(Logs folder); fk platform path)
BACKUP_Report.paths:=New object("settings"; $settings.path; "data"; $dataFile.path; "logs"; $logs.path)
BACKUP_Report.archivePlatformPath:=Folder($request.archives; fk posix path).platformPath
If (($settings.path#$request.settings) | ($dataFile.path#$request.data) | ($logs.path#$request.logs))
	BACKUP_Report.error:="Native backup paths do not match the isolated fixture"
	BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
	ON ERR CALL(BACKUP_PreviousHandler; ek local)
	QUIT 4D
	return
End if
If ($settings.getText()#$request.settingsContent)
	BACKUP_Report.error:="Native backup settings differ from the verified isolated configuration"
	BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
	ON ERR CALL(BACKUP_PreviousHandler; ek local)
	QUIT 4D
	return
End if
If ($request.configureOnly=True)
	BACKUP_Report.finished:=True
	BACKUP_Report.success:=True
	BACKUP_Report.phase:="paths verified"
	BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
	ON ERR CALL(BACKUP_PreviousHandler; ek local)
	QUIT 4D
	return
End if
BACKUP_Report.phase:="backup"
BACKUP_Report.backupAttempted:=True
BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
BACKUP
BACKUP_Report.backupOK:=OK
BACKUP_Report.phase:="direct host observation"
$direct:=New object("lastLocal"; ""; "nextLocal"; "")
BACKUP INFO(Last backup date; $date; $time)
If ($date#!0000-00-00!)
	$direct.lastLocal:=String($date; ISO date; $time)
End if
BACKUP INFO(Next backup date; $date; $time)
If ($date#!0000-00-00!)
	$direct.nextLocal:=String($date; ISO date; $time)
End if
BACKUP INFO(Last backup status; $number; $text)
$direct.statusCode:=$number
BACKUP INFO(Last backup information; $number; $text)
$direct.duration:=$number
$direct.beginUTC:=$text
BACKUP_Report.direct:=$direct
BACKUP_Report.phase:="component observation"
$collector:=cs.Dashboard._DashboardCollector.new()
$reading:=New object("availability"; "available"; \
	"last"; $collector.read("backupLast"); "next"; $collector.read("backupNext"); \
	"status"; $collector.read("backupStatus"); "information"; $collector.read("backupInformation"))
BACKUP_Report.component:=$collector._backupMetrics($reading)
BACKUP_Report.componentCompiled:=cs.Dashboard.Dashboard.new("macOS-universal")._cli.compiled
BACKUP_Report.success:=True
BACKUP_Report.finished:=True
BACKUP_Report.phase:="finished"
BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
ON ERR CALL(BACKUP_PreviousHandler; ek local)
QUIT 4D
