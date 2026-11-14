//%attributes = {"invisible":true,"preemptive":"capable"}
#DECLARE($operation : Text; $target : Text; $options : Object; $state : Object; $event : Object; $monitor : Object; $signal : 4D.Signal)
var Dashboard_Pending : cs._DashboardAgent
var Dashboard_State : Object
var $stopping : Boolean
Case of
	: ($operation="start")
		If (Dashboard_State#Null)
			Use ($state)
				$state.status:="failed"
				$state.error:="A dashboard is already active in this instance"
				$state.finished:=True
			End use
			CALL WORKER("Dashboard.callbacks."+ $state.epoch; "_DashboardSample"; "reject"; $state; $event; $monitor; Null; "failed")
			return
		End if
		Dashboard_State:=$state
		Dashboard_Pending:=cs._DashboardAgent.new($target; $options; $state; $event; $monitor)
		Dashboard_Pending.launch()
	: ($operation="adopted")
		If (Dashboard_State#Null)
			If (Dashboard_State.epoch=$state.epoch)
				Dashboard_Pending:=Null
			End if
		End if
	: ($operation="release")
		If (Dashboard_State#Null)
			If (Dashboard_State.epoch=$state.epoch)
				If ($state.port>0)
					cs.workers.worker.new(cs._DashboardServer).terminate($state.port)
				End if
				If (Dashboard_State#Null)
					If (Dashboard_State.epoch=$state.epoch)
						If (Not($state.forceDrain))
							Dashboard_Pending:=Null
							Dashboard_State:=Null
						End if
					End if
				End if
			End if
		End if
	: ($operation="drained")
		If (Dashboard_State#Null)
			If (Dashboard_State.epoch=$state.epoch)
				Dashboard_Pending:=Null
				Dashboard_State:=Null
				Use ($state)
					$state.finished:=True
				End use
				CALL WORKER("Dashboard.callbacks."+$state.epoch; "_DashboardSample"; "notify"; $state; New object; New object; Null; $state.status)
			End if
		End if
	: (($operation="stop") | ($operation="force") | ($operation="timeout"))
		If (Dashboard_State#Null)
			If (Dashboard_State.epoch=$state.epoch)
				If ($operation="timeout")
					If ($state.status="running")
						return
					End if
					Use ($state)
						$state.status:="failed"
						If ($state.error="")
							$state.error:="Dashboard startup timed out"
						End if
						$state.url:=""
					End use
				End if
				$stopping:=$state.stopRequested
				Use ($state)
					$state.stopRequested:=True
				End use
				If (Dashboard_Pending#Null)
					If ($operation="force")
						Dashboard_Pending.force()
					Else
						Dashboard_Pending.stop()
					End if
				Else
					If ($operation="force")
						Use ($state)
							$state.forceDrain:=True
						End use
						cs.workers.worker.new(cs._DashboardServer).terminate($state.port)
					End if
				End if
				If (($operation="stop") | ($operation="timeout"))
					If (Not($stopping))
						CALL WORKER("Dashboard.stop."+ $state.epoch; "_DashboardStop"; $state)
					End if
				End if
			End if
		End if
End case
If ($signal#Null)
	$signal.trigger()
End if
