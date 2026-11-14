//%attributes = {"invisible":true}
// Native safety probe: runs each case in order and records progress before every call, so a crash
// (which no error handler can catch) is attributed to the last case that started. Test tooling only.
var $ignored : Integer
var $parameter; $previous : Text
var $request; $status; $case : Object
var $requestFile; $statusFile : 4D.File
var $formula : 4D.Function
var $result : Variant
var Probe_Errors : Collection
$ignored:=Get database parameter(User param value; $parameter)
If (Is Windows)
	$requestFile:=File($parameter; fk platform path)
Else
	$requestFile:=File($parameter; fk posix path)
End if
$request:=JSON Parse($requestFile.getText())
If (Is Windows)
	$statusFile:=File($request.status; fk platform path)
Else
	$statusFile:=File($request.status; fk posix path)
End if
$status:=New object("finished"; False; "started"; ""; "cases"; New object)
For each ($case; $request.cases)
	$status.started:=$case.name
	$statusFile.setText(JSON Stringify($status))
	$previous:=Method called on error(ek local)
	Probe_Errors:=Null
	ON ERR CALL("Probe_error"; ek local)
	$formula:=Formula from string($case.code)
	$result:=$formula.call()
	ON ERR CALL($previous; ek local)
	If (Probe_Errors#Null)
		$status.cases[$case.name]:=New object("status"; "error"; "codes"; Probe_Errors.extract("errCode"))
	Else
		$status.cases[$case.name]:=New object("status"; "passed"; "resultType"; Value type($result))
		If ((Value type($result)=Is real) | (Value type($result)=Is longint) | (Value type($result)=Is boolean))
			// Scalars only: probe snippets must never return private text or objects.
			$status.cases[$case.name].value:=$result
		End if
	End if
	$status.started:=""
	$statusFile.setText(JSON Stringify($status))
End for each
$status.finished:=True
$statusFile.setText(JSON Stringify($status))
QUIT 4D
