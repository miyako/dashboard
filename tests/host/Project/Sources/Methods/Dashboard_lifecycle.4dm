//%attributes = {"invisible":true,"preemptive":"capable"}
#DECLARE($operation : Text; $target : Text; $state : Object; $signal : 4D.Signal)
var $agent : cs.Dashboard._DashboardAgent
var $retired; $resolved; $ready; $options : Object
var $worker : 4D.SystemWorker
var $deadline : Real
var $forceDrain : Boolean
Case of
	: ($operation="retired")
		Use ($signal)
			$signal.oldFinished:=True
			$signal.replacementOwned:=True
		End use
		For each ($forceDrain; New collection(False; True))
			$retired:=New shared object("status"; "stopped"; "url"; ""; "error"; ""; "samples"; 0; "epoch"; Generate UUID; "port"; $state.port; "finished"; True; "stopRequested"; True; "forceDrain"; $forceDrain)
			$agent:=cs.Dashboard._DashboardAgent.new($target; New object; $retired; New object; New object)
			// Deliver retired finalizers after a replacement owns the same real port.
			$agent.finish()
			Use ($signal)
				$signal.oldFinished:=$signal.oldFinished & $retired.finished
				$signal.replacementOwned:=$signal.replacementOwned & cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($state.port)
			End use
		End for each
	: ($operation="failure")
		$retired:=New shared object("status"; "running"; "url"; ""; "error"; ""; "samples"; 0; "epoch"; Generate UUID; "port"; 0; "finished"; False; "stopRequested"; False; "forceDrain"; False)
		$agent:=cs.Dashboard._DashboardAgent.new($target; New object; $retired; New object; New object)
		$resolved:=cs.Dashboard._CLI.new("dashboard"; $target).resolve()
		$ready:=New shared object("url"; "")
		$options:=New object("dataType"; "text"; "encoding"; "UTF-8"; "hideWindow"; True; "currentDirectory"; $resolved.file.parent; "buffer"; ""; "state"; $ready; "agent"; $agent; "onData"; Formula(Dashboard_blocker($1; $2)); "onTerminate"; Formula(This.agent.onTerminate($1; $2)))
		$worker:=4D.SystemWorker.new(cs.Dashboard._Process.new().quote($resolved.file.path)+" serve"; $options)
		$agent.worker:=$worker
		$deadline:=Milliseconds+3000
		While (($ready.url="") & Not($worker.terminated) & (Milliseconds<$deadline))
			$worker.wait(0.1)
		End while
		Use ($signal)
			$signal.running:=($ready.url#"") & Not($worker.terminated)
		End use
		$agent.fail("Injected running transport failure")
		Use ($signal)
			$signal.watchdog:=(Process number("Dashboard.stop."+$retired.epoch)#0)
		End use
		$worker.wait(2)
		Use ($signal)
			$signal.terminated:=$worker.terminated
			$signal.finished:=$retired.finished
			$signal.diagnostic:=($retired.error="Injected running transport failure")
		End use
		$deadline:=Milliseconds+3000
		While ((Process number("Dashboard.stop."+$retired.epoch)#0) & (Milliseconds<$deadline))
			$worker.wait(0.1)
		End while
		Use ($signal)
			$signal.pruned:=(Process number("Dashboard.stop."+$retired.epoch)=0)
		End use
End case
$signal.trigger()
