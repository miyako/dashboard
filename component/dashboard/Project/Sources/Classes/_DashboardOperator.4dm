// Operator actions: shared closed catalog (Resources/actions.json), strict validation, fail-closed audit.
// See docs/operator-actions.md and docs/admin-actions-design.md.
property actions : Collection
property epoch : Text
property folder : 4D.Folder
property seen : Collection
property relay : Boolean
property progressLog : Collection

Class constructor($actions : Collection; $epoch : Text; $folder : 4D.Folder)
	This.actions:=$actions
	This.epoch:=$epoch
	This.folder:=$folder
	This.seen:=New collection
	// Tests set relay to False and read progressLog instead of reaching a live agent.
	This.relay:=True
	This.progressLog:=New collection

Function catalog()->$catalog : Object
	// Keyed by action ID; object keys compare case-sensitively, unlike Collection.indexOf on Text.
	var $file : 4D.File
	var $parsed : Variant
	var $entry : Object
	$catalog:=New object
	$file:=Folder(fk resources folder).file("actions.json")
	If (Not($file.exists))
		return
	End if
	$parsed:=JSON Parse($file.getText())
	If (Value type($parsed)#Is object)
		return
	End if
	If (Value type($parsed.actions)#Is collection)
		return
	End if
	For each ($entry; $parsed.actions)
		$catalog[$entry.id]:=$entry
	End for each

Function logCatalog()->$catalog : Object
	// Log families keyed by ID, from Resources/logs.json (byte-identical to the CLI's copy).
	var $file : 4D.File
	var $parsed : Variant
	var $family : Object
	$catalog:=New object
	$file:=Folder(fk resources folder).file("logs.json")
	If (Not($file.exists))
		return
	End if
	$parsed:=JSON Parse($file.getText())
	If (Value type($parsed)#Is object)
		return
	End if
	If (Value type($parsed.families)#Is collection)
		return
	End if
	For each ($family; $parsed.families)
		$catalog[$family.id]:=$family
	End for each

Function validateLogs($value : Variant; $operatorEnabled : Boolean)->$result : Object
	var $catalog; $seen : Object
	var $id : Variant
	var $families : Collection
	$result:=New object("ok"; False; "error"; "logs must be an object with a families collection")
	If (Value type($value)#Is object)
		return
	End if
	If ((OB Keys($value).length#1) | (Value type($value.families)#Is collection))
		return
	End if
	If (Not($operatorEnabled))
		$result.error:="log browsing requires operator mode"
		return
	End if
	If (($value.families.length<1) | ($value.families.length>8))
		$result.error:="logs families must list 1 to 8 catalog IDs"
		return
	End if
	$catalog:=This.logCatalog()
	$seen:=New object
	$families:=New collection
	For each ($id; $value.families)
		If (Value type($id)#Is text)
			$result.error:="logs families must be unique catalog IDs"
			return
		End if
		If ((Value type($catalog[$id])#Is object) | ($seen[$id]=True))
			$result.error:="logs families must be unique catalog IDs"
			return
		End if
		$seen[$id]:=True
		$families.push($id)
	End for each
	$result:=New object("ok"; True; "families"; $families.orderBy())

Function checkLogAccess($message : Object; $families : Collection)->$result : Object
	// Strict validation of a CLI logAccess frame; returns the family entry when valid.
	var $field : Text
	var $family : Object
	$result:=New object("ok"; False; "error"; "Invalid dashboard log access frame")
	If (JSON Stringify(OB Keys($message).orderBy())#JSON Stringify(New collection("actor"; "epoch"; "family"; "file"; "id"; "kind"; "op"; "protocol")))
		return
	End if
	For each ($field; New collection("actor"; "epoch"; "family"; "file"; "id"; "op"))
		If (Value type($message[$field])#Is text)
			return
		End if
	End for each
	If (Not(Match regex("^[a-f0-9]{64}$"; $message.id)) | Not(Match regex("^[a-f0-9]{16}$"; $message.actor)) | ($message.op#"open"))
		return
	End if
	If ((Length($message.epoch)#Length(This.epoch)) | (Position(This.epoch; $message.epoch; *)#1))
		$result.error:="Dashboard log access for another epoch"
		return
	End if
	If ($families.indexOf($message.family)<0)
		$result.error:="Dashboard log family not enabled"
		return
	End if
	$family:=This.logCatalog()[$message.family]
	If ($family=Null)
		return
	End if
	If (Not(Match regex("^[A-Za-z0-9._-]{1,128}$"; $message.file)) | Not(Match regex($family.pattern; $message.file)))
		$result.error:="Dashboard log file outside its family"
		return
	End if
	If (This.seen.indexOf($message.id)>=0)
		$result.error:="Duplicate dashboard log access"
		return
	End if
	This.seen.push($message.id)
	If (This.seen.length>64)
		This.seen.shift()
	End if
	$result:=New object("ok"; True; "family"; $family)

Function logAccess($message : Object; $family : Object; $authorize : 4D.Function)->$frame : Object
	// Runs on the executor: host authorization (required for sensitive families), then the audit record, fail-closed.
	var $answer : Variant
	var $started : Integer
	var $canonical : Text
	var $record : Object
	$canonical:=JSON Stringify(New object("family"; $message.family; "file"; $message.file))
	$record:=New object("v"; 1; "at"; ""; "epoch"; This.epoch; "action"; "logs."+$message.op; 		"id"; Substring(Generate digest($message.id; SHA256 digest); 1; 16); "actor"; $message.actor; 		"args"; Substring(Generate digest($canonical; SHA256 digest); 1; 16); "state"; "completed")
	$frame:=New object("id"; $message.id; "ok"; True)
	If (($authorize#Null) | ($family.sensitivity="sensitive"))
		$answer:=False
		If ($authorize#Null)
			$started:=Milliseconds
			$answer:=Try($authorize.call(Null; New object("action"; "logs."+$message.op; "args"; JSON Parse($canonical); "actor"; $message.actor; "tier"; "logs")))
			If ((Last errors#Null) | ((Milliseconds-$started)>5000))
				$answer:=False
			End if
		End if
		If (Value type($answer)#Is boolean)
			$answer:=False
		End if
		If (Not($answer))
			$record.state:="failed"
			$record.error:="host_denied"
			This.audit($record)
			return New object("id"; $message.id; "ok"; False; "error"; "host_denied")
		End if
	End if
	If (Not(This.audit($record)))
		// Fail closed: no byte of a log is served without its audit record.
		return New object("id"; $message.id; "ok"; False; "error"; "audit_unavailable")
	End if

Function defaultFolder()->$folder : 4D.Folder
	// The host's Logs folder (*), never the component's.
	$folder:=Folder(fk logs folder; *).folder("dashboard")

Function validate($value : Variant; $catalog : Object)->$result : Object
	var $seen : Object
	var $id : Variant
	var $key : Text
	var $actions : Collection
	var $hostRequired : Boolean
	If ($catalog=Null)
		$catalog:=This.catalog()
	End if
	$result:=New object("ok"; False; "error"; "operator must be an object with an actions collection and an optional authorize formula")
	If (Value type($value)#Is object)
		return
	End if
	For each ($key; OB Keys($value))
		If (($key#"actions") & ($key#"authorize"))
			return
		End if
	End for each
	If (Value type($value.actions)#Is collection)
		return
	End if
	If (Value type($value.authorize)#Is undefined)
		If (Value type($value.authorize)#Is object)
			$result.error:="operator authorize must be a Formula or function"
			return
		End if
		If (Not(OB Instance of($value.authorize; 4D.Function)))
			$result.error:="operator authorize must be a Formula or function"
			return
		End if
	End if
	If (($value.actions.length<1) | ($value.actions.length>8))
		$result.error:="operator actions must list 1 to 8 catalog IDs"
		return
	End if
	$seen:=New object
	$actions:=New collection
	$hostRequired:=False
	For each ($id; $value.actions)
		If (Value type($id)#Is text)
			$result.error:="operator actions must be unique catalog IDs"
			return
		End if
		If ((Value type($catalog[$id])#Is object) | ($seen[$id]=True))
			$result.error:="operator actions must be unique catalog IDs"
			return
		End if
		If ($catalog[$id].approval="operator+host")
			$hostRequired:=True
		End if
		// "local" commands (for example SET CACHE SIZE) cannot run in 4D remote mode.
		If (($catalog[$id].scope="local") & (Application type=4D Remote mode))
			$result.error:="operator action "+$id+" is not available on a remote client"
			return
		End if
		$seen[$id]:=True
		$actions.push($id)
	End for each
	If ($hostRequired & (Value type($value.authorize)=Is undefined))
		$result.error:="tier B and C actions require an authorize callback"
		return
	End if
	$result:=New object("ok"; True; "actions"; $actions.orderBy())
	If (Value type($value.authorize)#Is undefined)
		$result.authorize:=$value.authorize
	End if

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

Function _arguments($message : Object; $entry : Object)->$canonical : Text
	// Generic catalog validation; returns sorted-key canonical JSON, or "" when invalid.
	var $name : Text
	var $names : Collection
	var $spec : Object
	var $value : Variant
	var $out : Object
	$canonical:=""
	$names:=OB Keys($entry.args).orderBy()
	If (JSON Stringify(OB Keys($message.args).orderBy())#JSON Stringify($names))
		return
	End if
	$out:=New object
	For each ($name; $names)
		$spec:=$entry.args[$name]
		$value:=$message.args[$name]
		Case of
			: ($spec.type="text")
				If (Value type($value)#Is text)
					return
				End if
				If (Not(Match regex($spec.pattern; $value)))
					return
				End if
			: ($spec.type="integer")
				If ((Value type($value)#Is real) & (Value type($value)#Is longint))
					return
				End if
				If (Int($value)#$value)
					return
				End if
				If (Value type($spec.enum)=Is collection)
					If ($spec.enum.indexOf($value)<0)
						return
					End if
				Else
					If (($value<$spec.min) | ($value>$spec.max))
						return
					End if
				End if
			Else
				return
		End case
		$out[$name]:=$value
	End for each
	$canonical:=JSON Stringify($out)

Function begin($message : Object)->$result : Object
	// Validates an action frame and writes its running audit record before anything executes.
	var $field : Text
	var $keys : Collection
	var $canonical : Text
	var $entry : Object
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
	$entry:=This.catalog()[$message.action]
	If ($entry=Null)
		$result.error:="Dashboard action not in catalog"
		return
	End if
	$canonical:=This._arguments($message; $entry)
	If ($canonical="")
		$result.error:="Invalid dashboard action arguments"
		return
	End if
	This.seen.push($message.id)
	If (This.seen.length>64)
		This.seen.shift()
	End if
	$result:=New object("ok"; True; "entry"; $entry; "canonical"; $canonical; "record"; New object("v"; 1; "at"; ""; "epoch"; This.epoch; "action"; $message.action; \
		"id"; Substring(Generate digest($message.id; SHA256 digest); 1; 16); "actor"; $message.actor; \
		"args"; Substring(Generate digest($canonical; SHA256 digest); 1; 16); "state"; "running"))
	If (This.audit($result.record))
		$result.frame:=New object("id"; $message.id; "state"; "running")
		If ($entry.exclusive=True)
			$result.frame.exclusive:=True
		End if
	Else
		// Fail closed: nothing runs without its audit record.
		$result.frame:=New object("id"; $message.id; "state"; "failed"; "error"; "audit_unavailable")
	End if

Function execute($message : Object; $record : Object; $entry : Object; $canonical : Text; $authorize : 4D.Function)->$frame : Object
	// Runs on the cooperative executor worker, never on .workers. Returns the final actionState frame.
	var $previous; $code : Text
	var $answer : Variant
	var $started; $index : Integer
	var $requested; $current; $physical; $actual : Real
	var CLI_LastErrors : Collection
	$frame:=New object("id"; $message.id; "state"; "failed"; "error"; "host_denied")
	If (($authorize#Null) | ($entry.approval="operator+host"))
		$answer:=False
		If ($authorize#Null)
			$started:=Milliseconds
			// Try, like the onStatus callback: a component's error handler does not cover host code.
			$answer:=Try($authorize.call(Null; New object("action"; $message.action; "args"; JSON Parse($canonical); "actor"; $message.actor; "tier"; $entry.tier)))
			If ((Last errors#Null) | ((Milliseconds-$started)>5000))
				$answer:=False
			End if
		End if
		If (Value type($answer)#Is boolean)
			$answer:=False
		End if
		If (Not($answer))
			$record.state:="failed"
			$record.error:="host_denied"
			This.audit($record)
			return
		End if
	End if
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	Case of
		: ($message.action="operator.noop")
			// Changes nothing by design: proves the pipeline without a mutator.
		: (($message.action="operator.sleep") | ($message.action="operator.exclusiveSleep"))
			// Harmless timed work: proves the executor, progress, pause and deadlines.
			For ($index; 1; $message.args.seconds)
				DELAY PROCESS(Current process; 60)
				This._progress($message.id; "sleeping"; Int(100*$index/$message.args.seconds); $entry)
			End for
		: (($message.action="monitor.cadence") | ($message.action="monitor.diagnostics"))
			// Owner approval and audit only: the Go CLI applies these after this completed state.
		: ($message.action="cache.flush")
			// Plain form only: the size and * forms are documented as reserved for testing.
			FLUSH CACHE
		: ($message.action="cache.size")
			// Lowering is always allowed (4D's floor is 100 MiB). Raising is capped at 75% of physical memory.
			$requested:=$message.args.sizeMiB*1048576
			$current:=Get cache size
			$physical:=Num(System info.physicalMemory)*1024
			If (($requested>$current) & (($physical<=0) | ($requested>($physical*0.75))))
				ON ERR CALL($previous; ek local)
				$record.state:="failed"
				$record.error:="cache_size_policy"
				This.audit($record)
				return New object("id"; $message.id; "state"; "failed"; "error"; "cache_size_policy")
			End if
			SET CACHE SIZE($requested)
			$actual:=Get cache size
			If (Abs($actual-$requested)>1048576)
				ON ERR CALL($previous; ek local)
				$record.state:="failed"
				$record.error:="postcondition_unmet"
				This.audit($record)
				return New object("id"; $message.id; "state"; "failed"; "error"; "postcondition_unmet")
			End if
	End case
	ON ERR CALL($previous; ek local)
	If (CLI_LastErrors#Null)
		// Closed code only: native messages can contain private paths.
		$code:=String(Abs(Num(CLI_LastErrors[0].errCode)))
		CLI_LastErrors:=Null
		$record.state:="failed"
		$record.error:="native_error_"+$code
		$frame:=New object("id"; $message.id; "state"; "failed"; "error"; $record.error)
		This.audit($record)
		return
	End if
	$record.state:="completed"
	$frame:=New object("id"; $message.id; "state"; "completed")
	If ($entry.verify="none")
		$frame.unverified:=True
	End if
	If (Not(This.audit($record)))
		$frame.error:="audit_incomplete"
	End if

Function _progress($id : Text; $phase : Text; $percent : Integer; $entry : Object)
	var $frame : Object
	$frame:=New object("id"; $id; "state"; "running"; "progress"; New object("phase"; $phase; "percent"; $percent))
	If ($entry.exclusive=True)
		$frame.exclusive:=True
	End if
	If (This.relay)
		CALL WORKER(".workers"; "_DashboardRelay"; "progress"; This.epoch; $frame)
	Else
		This.progressLog.push($frame)
	End if

Function complete($message : Object; $record : Object)->$frame : Object
	// Synchronous path kept for unit tests of the M3/M4 actions; live actions use execute on the executor.
	var $entry : Object
	$entry:=This.catalog()[$message.action]
	$frame:=This.execute($message; $record; $entry; This._arguments($message; $entry); Null)

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
