//%attributes = {"invisible":true}
var Probe_Errors : Collection
If (Probe_Errors=Null)
	Probe_Errors:=New collection
End if
Probe_Errors.combine(Last errors)
