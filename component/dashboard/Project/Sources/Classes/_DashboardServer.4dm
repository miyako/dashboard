property agent : cs._DashboardAgent

Class constructor()

Function start($params : Object)->$worker : 4D.SystemWorker
	// Adoption runs reentrantly on .workers; the already-bound controller is not copied.
	This.agent:=$params.agent
	$worker:=This.agent.worker

Function isReady($port : Integer)->$ready : Boolean
	$ready:=(This.agent.state.status="running")
