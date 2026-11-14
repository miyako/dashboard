//%attributes = {"invisible":true}
// Test-only: polls operator status until the action reaches one of $states or $timeout ms pass.
// Returns {record, status} from the last read; record is Null when the action was not listed.
#DECLARE($origin : Text; $cookie : Text; $id : Text; $states : Collection; $timeout : Integer)->$result : Object
var $deadline : Integer
var $status : Variant
var $record : Object
$deadline:=Milliseconds+$timeout
$result:=New object("record"; Null; "status"; Null)
Repeat
	$status:=JSON Parse(Operator_http("GET"; $origin+"/api/operator/status"; New object("Cookie"; $cookie); "").body)
	$record:=Null
	If (Value type($status)=Is object)
		$record:=$status.records.query("id = :1"; $id).first()
	End if
	$result:=New object("record"; $record; "status"; $status)
	If ($record#Null)
		If ($states.indexOf($record.state)>=0)
			return
		End if
	End if
	DELAY PROCESS(Current process; 6)
Until (Milliseconds>$deadline)
