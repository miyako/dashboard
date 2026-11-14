//%attributes = {"invisible":true}
// Test-only null-safe path read: Operator_field($o; "record.progress.phase") is Null when any step is missing.
#DECLARE($object : Variant; $path : Text)->$value : Variant
var $key : Text
$value:=$object
For each ($key; Split string($path; "."))
	If (Value type($value)#Is object)
		$value:=Null
		return
	End if
	$value:=$value[$key]
End for each
