//%attributes = {"invisible":true}
// Test-only: waits for the next completed sample as a baseline, then returns $count real intervals (ms) between samples.
#DECLARE($state : Object; $count : Integer; $timeout : Integer)->$intervals : Collection
var $samples; $last; $deadline : Integer
$intervals:=New collection
$deadline:=Milliseconds+$timeout
$samples:=$state.samples
While (($state.samples=$samples) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 1)
End while
$samples:=$state.samples
$last:=Milliseconds
While (($intervals.length<$count) & (Milliseconds<$deadline) & ($state.status="running"))
	DELAY PROCESS(Current process; 1)
	If ($state.samples#$samples)
		$intervals.push(Milliseconds-$last)
		$last:=Milliseconds
		$samples:=$state.samples
	End if
End while
