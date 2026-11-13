//%attributes = {"invisible":true}
#DECLARE($operation : Text; $target : Text; $options : Object; $state : Object)
var Dashboard_Agent : cs._DashboardAgent
Case of
	: ($operation="start")
		If (Dashboard_Agent#Null)
			Use ($state)
				$state.status:="failed"
				$state.error:="A dashboard is already active in this instance"
			End use
		Else
			Dashboard_Agent:=cs._DashboardAgent.new($target; $options; $state)
			Dashboard_Agent.launch()
		End if
	: ($operation="stop")
		If (Dashboard_Agent#Null)
			Dashboard_Agent.stop()
			Dashboard_Agent:=Null
		End if
		KILL WORKER
End case
