//%attributes = {"invisible":true}
// Test-only: requests and confirms one operator action over HTTP; returns its action ID ("" on failure).
#DECLARE($origin : Text; $headers : Object; $action : Text; $args : Object)->$id : Text
var $response : Object
var $body : Variant
$id:=""
$response:=Operator_http("POST"; $origin+"/api/operator/request"; $headers; JSON Stringify(New object("action"; $action; "args"; $args)))
If ($response.status#201)
	return
End if
$body:=JSON Parse($response.body)
$response:=Operator_http("POST"; $origin+"/api/operator/confirm"; $headers; JSON Stringify(New object("confirmation"; $body.confirmation; "action"; $action; "args"; $args)))
If ($response.status=202)
	$id:=$body.id
End if
