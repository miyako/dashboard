//%attributes = {"invisible":true}
#DECLARE($worker : 4D.SystemWorker; $event : Object)
var $position : Integer
var $message : Object
This.buffer+=$event.data
$position:=Position(Char(10); This.buffer; *)
If ($position>0)
	$message:=JSON Parse(Substring(This.buffer; 1; $position-1))
	Use (This.state)
		This.state.url:=$message.url
	End use
End if
