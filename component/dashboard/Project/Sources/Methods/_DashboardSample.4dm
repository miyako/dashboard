//%attributes = {"invisible":true,"preemptive":"incapable"}
#DECLARE($operation : Text; $state : Object; $event : Object; $monitor : Object; $signal : 4D.Signal; $kind : Text; $status : Object)
var Dashboard_Sampler : cs._DashboardSampler
var $previous : Text
var CLI_LastErrors : Collection
If (Dashboard_Sampler=Null)
	Dashboard_Sampler:=cs._DashboardSampler.new($state; $event; $monitor)
End if
Case of
	: ($operation="sample")
		$previous:=Method called on error(ek local)
		CLI_LastErrors:=Null
		ON ERR CALL("_CaptureError"; ek local)
		Dashboard_Sampler.sample($signal)
		ON ERR CALL($previous; ek local)
		If (CLI_LastErrors#Null)
			Use ($signal)
				$signal.error:=JSON Stringify(CLI_LastErrors)
			End use
			$signal.trigger()
		End if
		CLI_LastErrors:=Null
	: (($operation="notify") | ($operation="reject"))
		Dashboard_Sampler.notify($kind; $status)
		If (Dashboard_Sampler.terminal & Not(Dashboard_Sampler.notifying))
			Dashboard_Sampler:=Null
			KILL WORKER
		End if
End case
