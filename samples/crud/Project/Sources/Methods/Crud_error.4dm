//%attributes = {"invisible":true}
var CRUD_StatusFile : 4D.File
var CRUD_Monitor : cs.Dashboard.Dashboard
var CRUD_PreviousHandler : Text
var $errors : Collection
$errors:=Last errors
ON ERR CALL(CRUD_PreviousHandler; ek local)
CRUD_StatusFile.setText(JSON Stringify(New object("success"; False; "finished"; False; "errors"; $errors)))
CRUD_Monitor.stop()
DELAY PROCESS(Current process; 60)
QUIT 4D
