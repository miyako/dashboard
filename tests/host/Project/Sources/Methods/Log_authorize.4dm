//%attributes = {"invisible":true}
// Test host authorize callback for log access: records each request (it runs on the component's executor worker) and allows it.
#DECLARE($request : Object)->$allowed : Boolean
Use (Storage)
	If (Storage.logCalls=Null)
		Storage.logCalls:=New shared collection
	End if
End use
Use (Storage.logCalls)
	Storage.logCalls.push(OB Copy($request; ck shared; Storage.logCalls))
End use
$allowed:=True
