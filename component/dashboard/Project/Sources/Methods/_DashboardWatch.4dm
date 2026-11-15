//%attributes = {"invisible":true,"preemptive":"capable"}
// One timer per dashboard instance ("Dashboard.watch.<epoch>"): ticks the agent on .workers once a second
// for restart delays, liveness and forced stops, so .workers itself never sleeps. Ends with the instance.
#DECLARE($state : Object)
While (Not($state.finished))
	DELAY PROCESS(Current process; 60)
	If (Not($state.finished))
		CALL WORKER(".workers"; "_DashboardWorker"; "tick"; ""; New object; $state; New object; New object)
	End if
End while
KILL WORKER
