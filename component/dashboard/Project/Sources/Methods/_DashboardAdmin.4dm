//%attributes = {"invisible":true,"preemptive":"incapable"}
// Executor for operator actions: one cooperative worker per dashboard epoch ("Dashboard.admin.<epoch>").
// Cooperative so that commands that are not thread-safe can run; actions run one at a time, in order.
// The result goes back to .workers through _DashboardRelay, which routes it to the agent of the same epoch.
#DECLARE($operation : Text; $epoch : Text; $message : Object; $record : Object; $entry : Object; $canonical : Text; $actions : Collection; $folderPath : Text; $authorize : 4D.Function)
var $operator : cs._DashboardOperator
var $frame : Object
Case of
	: ($operation="run")
		$operator:=cs._DashboardOperator.new($actions; $epoch; Folder($folderPath; fk platform path))
		$frame:=$operator.execute($message; $record; $entry; $canonical; $authorize)
		CALL WORKER(".workers"; "_DashboardRelay"; "final"; $epoch; $frame; $record; $folderPath)
	: ($operation="logAccess")
		// $entry carries the log family; nothing is read here, only authorized and audited.
		$operator:=cs._DashboardOperator.new($actions; $epoch; Folder($folderPath; fk platform path))
		$frame:=$operator.logAccess($message; $entry; $authorize)
		CALL WORKER(".workers"; "_DashboardRelay"; "logResult"; $epoch; $frame; Null; $folderPath)
	: ($operation="stop")
		KILL WORKER
End case
