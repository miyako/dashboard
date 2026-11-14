//%attributes = {"invisible":true}
// Test-only HTTP client for the live operator phase: returns status, text body and Set-Cookie name/value pairs.
#DECLARE($method : Text; $url : Text; $headers : Object; $body : Text)->$result : Object
var $request : 4D.HTTPRequest
var $options : Object
var $value : Variant
var $cookies : Collection
var $cookie; $pair : Text
var $equals; $semicolon : Integer
$options:=New object("method"; $method; "headers"; $headers; "dataType"; "text"; "timeout"; 5)
If ($method="POST")
	$options.body:=$body
End if
$request:=4D.HTTPRequest.new($url; $options)
$request.wait(10)
$result:=New object("status"; 0; "body"; ""; "cookies"; New object)
If ($request.response=Null)
	return
End if
$result.status:=$request.response.status
If (Value type($request.response.body)=Is text)
	$result.body:=$request.response.body
End if
$cookies:=New collection
$value:=$request.response.headers["set-cookie"]
Case of
	: (Value type($value)=Is text)
		$cookies.push($value)
	: (Value type($value)=Is collection)
		$cookies:=$value
End case
For each ($cookie; $cookies)
	$semicolon:=Position(";"; $cookie; *)
	$pair:=$cookie
	If ($semicolon>0)
		$pair:=Substring($cookie; 1; $semicolon-1)
	End if
	$equals:=Position("="; $pair; *)
	If ($equals>1)
		$result.cookies[Substring($pair; 1; $equals-1)]:=Substring($pair; $equals+1)
	End if
End for each
