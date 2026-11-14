//%attributes = {"invisible":true}
#DECLARE($state : Object; $startup : Boolean)
var $deadline : Real
$deadline:=Milliseconds+3500
If ($startup)
	$deadline:=Milliseconds+10000
End if
While (Not($state.finished) & (Milliseconds<$deadline))
	If ($startup & ($state.status="running"))
		KILL WORKER
		return
	End if
	DELAY PROCESS(Current process; 6)
End while
If (Not($state.finished))
	If ($startup)
		CALL WORKER(".workers"; "_DashboardWorker"; "timeout"; ""; New object; $state; New object; New object)
	Else
		var $signal : 4D.Signal
		var $manager : cs.workers.worker
		$signal:=New signal
		CALL WORKER(".workers"; "_DashboardWorker"; "force"; ""; New object; $state; New object; New object; $signal)
		If ($signal.wait(5))
			If ($state.forceDrain)
				// No replacement is admitted until the public API has drained retired workers.
				$manager:=cs.workers.worker.new(cs._DashboardServer)
				$manager.timeout:=5
				If ($manager.terminate($state.port))
					CALL WORKER(".workers"; "_DashboardWorker"; "drained"; ""; New object; $state; New object; New object)
				Else
					Use ($state)
						$state.status:="failed"
						$state.cleanupError:="Dashboard termination did not drain: "+JSON Stringify($manager.errors)
						If ($state.error="")
							$state.error:=$state.cleanupError
						End if
					End use
				End if
			End if
		Else
			Use ($state)
				$state.status:="failed"
				$state.cleanupError:="Dashboard termination dispatch timed out"
				If ($state.error="")
					$state.error:=$state.cleanupError
				End if
			End use
		End if
	End if
End if
KILL WORKER
