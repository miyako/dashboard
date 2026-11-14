//%attributes = {"invisible":true}
// Test host authorize callback: records each request (it runs on the component's executor worker) and allows it.
#DECLARE($request : Object)->$allowed : Boolean
Use (Storage)
	If (Storage.adminCalls=Null)
		Storage.adminCalls:=New shared collection
	End if
End use
Use (Storage.adminCalls)
	Storage.adminCalls.push(OB Copy($request; ck shared; Storage.adminCalls))
End use
$allowed:=True
