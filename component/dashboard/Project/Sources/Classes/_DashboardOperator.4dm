// Operator actions: closed catalog, strict validation and fail-closed audit. See docs/operator-actions.md.
property actions : Collection
property epoch : Text
property folder : 4D.Folder
property seen : Collection

Class constructor($actions : Collection; $epoch : Text; $folder : 4D.Folder)
	This.actions:=$actions
	This.epoch:=$epoch
	This.folder:=$folder
	This.seen:=New collection

Function catalog()->$catalog : Object
	// Object keys compare case-sensitively, unlike Collection.indexOf on Text.
	$catalog:=New object("operator.noop"; True)

Function defaultFolder()->$folder : 4D.Folder
	// The host's Logs folder (*), never the component's.
	$folder:=Folder(fk logs folder; *).folder("dashboard")

Function validate($value : Variant)->$result : Object
	var $catalog; $seen : Object
	var $id : Variant
	var $actions : Collection
	$result:=New object("ok"; False; "error"; "operator must be an object with only an actions collection")
	If (Value type($value)#Is object)
		return
	End if
	If (OB Keys($value).length#1)
		return
	End if
	If (Value type($value.actions)#Is collection)
		return
	End if
	If (($value.actions.length<1) | ($value.actions.length>8))
		$result.error:="operator actions must list 1 to 8 catalog IDs"
		return
	End if
	$catalog:=This.catalog()
	$seen:=New object
	$actions:=New collection
	For each ($id; $value.actions)
		If (Value type($id)#Is text)
			$result.error:="operator actions must be unique catalog IDs"
			return
		End if
		If (($catalog[$id]#True) | ($seen[$id]=True))
			$result.error:="operator actions must be unique catalog IDs"
			return
		End if
		$seen[$id]:=True
		$actions.push($id)
	End for each
	$result:=New object("ok"; True; "actions"; $actions.orderBy())

Function enabled($id : Text)->$enabled : Boolean
	var $action : Text
	$enabled:=False
	For each ($action; This.actions)
		If (Length($action)=Length($id))
			If (Position($action; $id; *)=1)
				$enabled:=True
			End if
		End if
	End for each

Function _arguments($message : Object)->$canonical : Text
	// Returns the canonical JSON of valid arguments, or "" when invalid.
	$canonical:=""
	Case of
		: ($message.action="operator.noop")
			If (OB Keys($message.args).length#1)
				return
			End if
			If (Value type($message.args.note)#Is text)
				return
			End if
			If (Not(Match regex("^[A-Za-z0-9 _.-]{1,32}$"; $message.args.note)))
				return
			End if
			$canonical:=JSON Stringify(New object("note"; $message.args.note))
	End case

Function begin($message : Object)->$result : Object
	// Validates an action frame and writes its running audit record before anything executes.
	var $field : Text
	var $keys : Collection
	var $canonical : Text
	$result:=New object("ok"; False; "error"; "Invalid dashboard action frame")
	$keys:=OB Keys($message).orderBy()
	If (JSON Stringify($keys)#JSON Stringify(New collection("action"; "actor"; "args"; "epoch"; "id"; "kind"; "protocol")))
		return
	End if
	For each ($field; New collection("action"; "actor"; "epoch"; "id"))
		If (Value type($message[$field])#Is text)
			return
		End if
	End for each
	If (Value type($message.args)#Is object)
		return
	End if
	If (Not(Match regex("^[a-f0-9]{64}$"; $message.id)) | Not(Match regex("^[a-f0-9]{16}$"; $message.actor)))
		return
	End if
	If (Length($message.epoch)#Length(This.epoch))
		$result.error:="Dashboard action for another epoch"
		return
	End if
	If (Position(This.epoch; $message.epoch; *)#1)
		$result.error:="Dashboard action for another epoch"
		return
	End if
	If (Not(This.enabled($message.action)))
		$result.error:="Dashboard action not enabled"
		return
	End if
	If (This.seen.indexOf($message.id)>=0)
		$result.error:="Duplicate dashboard action"
		return
	End if
	$canonical:=This._arguments($message)
	If ($canonical="")
		$result.error:="Invalid dashboard action arguments"
		return
	End if
	This.seen.push($message.id)
	If (This.seen.length>64)
		This.seen.shift()
	End if
	$result:=New object("ok"; True; "record"; New object("v"; 1; "at"; ""; "epoch"; This.epoch; "action"; $message.action; \
		"id"; Substring(Generate digest($message.id; SHA256 digest); 1; 16); "actor"; $message.actor; \
		"args"; Substring(Generate digest($canonical; SHA256 digest); 1; 16); "state"; "running"))
	If (This.audit($result.record))
		$result.frame:=New object("id"; $message.id; "state"; "running")
	Else
		// Fail closed: nothing runs without its audit record.
		$result.frame:=New object("id"; $message.id; "state"; "failed"; "error"; "audit_unavailable")
	End if

Function complete($message : Object; $record : Object)->$frame : Object
	Case of
		: ($message.action="operator.noop")
			// Changes nothing by design: proves the pipeline without a mutator.
	End case
	$record.state:="completed"
	$frame:=New object("id"; $message.id; "state"; "completed")
	If (Not(This.audit($record)))
		$frame.error:="audit_incomplete"
	End if

Function audit($record : Object)->$ok : Boolean
	var $previous : Text
	var $file; $rotated : 4D.File
	var $handle : 4D.FileHandle
	var $index : Integer
	var $written : Boolean
	var CLI_LastErrors : Collection
	$written:=False
	$record.at:=Timestamp
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	If (Not(This.folder.exists))
		This.folder.create()
	End if
	$file:=This.folder.file("audit.jsonl")
	If ($file.exists)
		If ($file.size>=1048576)
			For ($index; 3; 1; -1)
				$rotated:=This.folder.file("audit."+String($index)+".jsonl")
				If ($rotated.exists)
					If ($index=3)
						$rotated.delete()
					Else
						$rotated.rename("audit."+String($index+1)+".jsonl")
					End if
				End if
			End for
			$file.rename("audit.1.jsonl")
			$file:=This.folder.file("audit.jsonl")
		End if
	End if
	If (CLI_LastErrors=Null)
		$handle:=$file.open("append")
		If ($handle#Null)
			$handle.writeText(JSON Stringify($record)+Char(10))
			$written:=True
		End if
	End if
	$handle:=Null
	ON ERR CALL($previous; ek local)
	$ok:=(CLI_LastErrors=Null) & $written
	CLI_LastErrors:=Null
