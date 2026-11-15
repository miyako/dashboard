//%attributes = {"invisible":true,"preemptive":"capable"}
// Runs on .workers, the only sender to the CLI: forwards executor frames to the live agent of the same epoch.
// A final result for an epoch that has ended is audited as orphaned and never sent to a newer instance.
#DECLARE($operation : Text; $epoch : Text; $frame : Object; $record : Object; $folderPath : Text)
var Dashboard_Live : cs._DashboardAgent
var $live : Boolean
var $orphan : Object
$live:=False
If (Dashboard_Live#Null)
	If (Dashboard_Live.epoch=$epoch)
		If (Not(Dashboard_Live.closing) & Not(Dashboard_Live.state.finished))
			$live:=True
		End if
	End if
End if
If ($live)
	Dashboard_Live.send("actionState"; $frame)
	If ($operation="final")
		// The pause for an exclusive action is over: restart the liveness clock.
		Dashboard_Live.exclusiveRunning:=False
		Dashboard_Live.lastFrameAt:=Milliseconds
	End if
	return
End if
If ($operation="final")
	$orphan:=OB Copy($record)
	$orphan.state:="orphaned"
	$orphan.error:=String($frame.state)
	cs._DashboardOperator.new(New collection; $epoch; Folder($folderPath; fk platform path)).audit($orphan)
End if
