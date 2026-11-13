//%attributes = {"invisible":true}
var BACKUP_StatusFile : 4D.File
var BACKUP_Report : Object
var BACKUP_PreviousHandler : Text
BACKUP_Report.errors:=Last errors
ON ERR CALL(BACKUP_PreviousHandler; ek local)
BACKUP_StatusFile.setText(JSON Stringify(BACKUP_Report))
QUIT 4D
