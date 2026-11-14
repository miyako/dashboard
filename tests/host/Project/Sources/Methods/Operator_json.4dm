//%attributes = {"invisible":true}
// Test-only: parses an Operator_http response body, or returns an object with httpStatus when it is not JSON.
#DECLARE($response : Object)->$value : Object
If (Substring($response.body; 1; 1)="{")
	$value:=JSON Parse($response.body)
Else
	$value:=New object("httpStatus"; $response.status)
End if
