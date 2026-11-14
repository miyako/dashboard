//%attributes = {"invisible":true}
// Test-only: polls operator status until the action reaches one of $states or $timeout ms pass.
// Returns {record, status} from the last read; record is Null when the action was not listed.
#DECLARE($origin : Text; $cookie : Text; $id : Text; $states : Collection; $timeout : Integer)->$result : Object
var $deadline : Integer
var $status : Variant
var $record; $response : Object
$deadline:=Milliseconds+$timeout
$result:=New object("record"; Null; "status"; Null)
Repeat
	$response:=Operator_http("GET"; $origin+"/api/operator/status"; New object("Cookie"; $cookie); "")
	If (($response.status#200) | (Substring($response.body; 1; 1)#"{"))
		// Report the failed read instead of crashing on an empty or non-JSON body.
		$result:=New object("record"; Null; "status"; Null; "httpStatus"; $response.status)
		return
	End if
	$status:=JSON Parse($response.body)
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
