property info : Object
property staticMetrics : Collection
property sampleCount : Integer
property remote : Boolean
property licenseProducts : Object
property backupMetrics : Collection
property backupReadAt : Real
property encryptionMetrics : Collection
property encryptionReadAt : Real

Class constructor
	var $system; $license; $read : Object
	var $role; $platform : Text
	This.sampleCount:=0
	This.licenseProducts:=New object
	This.remote:=(Application type=4D Remote mode)
	$role:="standalone"
	Case of
		: (This.remote)
			$role:="client"
		: (Application type=4D Server)
			$role:="server"
		: (Application type=tool4d)
			$role:="tool4d"
	End case
	$platform:="unsupported"
	If (Is macOS)
		$platform:="macOS"
	End if
	If (Is Windows)
		$platform:="Windows"
	End if
	This.info:=New object("role"; $role; "platform"; $platform; "version"; Application version; "scope"; "collecting instance"; "protocol"; "1"; "capabilities"; "refresh,snapshot"; "privacy"; "allowlisted fields only")
	This.staticMetrics:=New collection
	This.staticMetrics.push(This.metric("app.type"; "Application type"; "number"; ""; "static"; Application type))
	This.staticMetrics.push(This.metric("app.versionType"; "Version type bitfield"; "number"; ""; "static"; Version type))
	This.staticMetrics.push(This.metric("app.compiled"; "Host compiled"; "boolean"; ""; "static"; Is compiled mode(*)))
	$read:=This.read("system")
	If ($read.ok)
		$system:=$read.data
		This.staticMetrics.push(This.metric("system.os"; "Operating system"; "text"; ""; "static"; $system.osVersion))
		This.staticMetrics.push(This.metric("system.cores"; "CPU cores"; "number"; "cores"; "static"; $system.cores))
		This.staticMetrics.push(This.metric("system.memory"; "Physical memory"; "number"; "KiB"; "static"; $system.physicalMemory))
	Else
		This.staticMetrics.push(This.unavailable("system.info"; "System information"; "text"; ""; "static"; "error"; "System info failed"))
	End if
	// License info reloads license rights; call once, never on the sampling path.
	$read:=This.read("license")
	If ($read.ok)
		$license:=$read.data
		If ($license#Null)
			This.staticMetrics.push(This.metric("license.product"; "Licensed product"; "text"; ""; "static"; $license.name))
		Else
			This.staticMetrics.push(This.unavailable("license.product"; "Licensed product"; "text"; ""; "static"; "unsupported"; "No local license (for example a remote client or tool4d)"))
		End if
	Else
		This.staticMetrics.push(This.unavailable("license.product"; "Licensed product"; "text"; ""; "static"; "error"; "License info failed"))
	End if
	For each ($read; This._datastoreMetrics(This.read("datastore")))
		This.staticMetrics.push($read)
	End for each

Function read($command : Text)->$result : Object
	var $previous : Text
	var $data : Variant
	var $store; $class : Object
	var $classes : Collection
	var $name : Text
	var $date : Date
	var $time : Time
	var $number : Integer
	var $text : Text
	var CLI_LastErrors : Collection
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	Case of
		: ($command="application")
			$data:=Application info
		: ($command="system")
			$data:=System info
		: ($command="license")
			$data:=License info
		: ($command="licenseUsage")
			$data:=License usage
		: ($command="cache")
			$data:=Cache info(New object("dbFilter"; "All"))
		: ($command="measures")
			$data:=Database measures(New object("withHistory"; False; "path"; New collection("DB.diskReadBytes"; "DB.diskWriteBytes"; "DB.cacheReadBytes"; "DB.cacheMissBytes"; "DB.diskReadCount"; "DB.diskWriteCount"; "DB.cacheReadCount"; "DB.cacheMissCount")))
		: ($command="activity")
			$data:=Process activity
		: ($command="backupContext")
			$store:=ds
			If ($store#Null)
				$data:=$store.getInfo()
			Else
				$data:=Null
			End if
		: ($command="backupLast")
			BACKUP INFO(Last backup date; $date; $time)
			$data:=New object("local"; "")
			If ($date#!0000-00-00!)
				$data.local:=String($date; ISO date; $time)
			End if
		: ($command="backupNext")
			BACKUP INFO(Next backup date; $date; $time)
			$data:=New object("local"; "")
			If ($date#!0000-00-00!)
				$data.local:=String($date; ISO date; $time)
			End if
		: ($command="backupStatus")
			BACKUP INFO(Last backup status; $number; $text)
			// Native status text can contain private paths; never return it.
			$data:=New object("code"; $number)
		: ($command="backupInformation")
			$number:=-1
			BACKUP INFO(Last backup information; $number; $text)
			$data:=New object("duration"; $number; "begin"; $text)
		: ($command="datastore")
			$store:=ds
			If ($store#Null)
				$classes:=New collection
				$data:=New object("info"; $store.getInfo(); "classes"; $classes)
				// Enumerate model properties only; never query entities or copy the datastore.
				For each ($name; $store)
					If ($classes.length=512)
						$data.limitExceeded:=True
						break
					End if
					$class:=$store[$name]
					$classes.push($class.getInfo())
					If (CLI_LastErrors#Null)
						break
					End if
				End for each
			Else
				$data:=Null
			End if
		: ($command="encryption")
			// Returns names/numbers of encryptable tables; only booleans and counts leave the normalizer.
			$store:=ds
			If ($store#Null)
				$data:=$store.encryptionStatus()
			Else
				$data:=Null
			End if
		: ($command="locked")
			$store:=ds
			If ($store#Null)
				$data:=$store.locked()
			Else
				$data:=Null
			End if
		: ($command="web")
			// Option 2 targets the host's web server; omitting it would read this component's own.
			$data:=WEB Server(Web server host database)
		: ($command="adminProtected")
			$store:=ds
			If ($store#Null)
				$data:=$store.isAdminProtected()
			Else
				$data:=Null
			End if
	End case
	ON ERR CALL($previous; ek local)
	$result:=New object("ok"; CLI_LastErrors=Null; "data"; $data)
	If (CLI_LastErrors#Null)
		// -33/33 "Unimplemented command or function": this runtime (for example tool4d) lacks the command.
		$result.unimplemented:=(CLI_LastErrors.query("errCode = :1"; 33).length>0)
	End if
	CLI_LastErrors:=Null

Function metric($id : Text; $label : Text; $type : Text; $unit : Text; $kind : Text; $value : Variant)->$metric : Object
	var $valid : Boolean
	$valid:=False
	Case of
		: ($type="number")
			$valid:=((Value type($value)=Is real) | (Value type($value)=Is longint))
		: ($type="text")
			$valid:=(Value type($value)=Is text)
		: ($type="boolean")
			$valid:=(Value type($value)=Is boolean)
	End case
	If ($valid)
		$metric:=New object("id"; $id; "label"; $label; "type"; $type; "unit"; $unit; "kind"; $kind; "availability"; "available"; "value"; $value)
	Else
		$metric:=This.unavailable($id; $label; $type; $unit; $kind; "missing"; "Command did not provide a value of the expected type")
	End if

Function unavailable($id : Text; $label : Text; $type : Text; $unit : Text; $kind : Text; $status : Text; $reason : Text)->$metric : Object
	$metric:=New object("id"; $id; "label"; $label; "type"; $type; "unit"; $unit; "kind"; $kind; "availability"; $status; "reason"; $reason)

Function _datastoreMetrics($read : Object)->$metrics : Collection
	var $info; $data : Object
	var $entry : Variant
	var $status; $reason; $field; $type; $unit; $label : Text
	var $exposed : Integer
	$metrics:=New collection
	$status:="error"
	$reason:="Datastore metadata failed"
	If ($read.ok)
		Case of
			: ($read.data=Null)
				$status:="unsupported"
				$reason:="No datastore available in this host"
			: (Value type($read.data)#Is object)
				$reason:="Invalid datastore metadata"
			Else
				$data:=$read.data
				If (Value type($data.info)=Is object)
					$info:=$data.info
					If (Value type($info.type)=Is text)
						If (($info.type="4D") | ($info.type="4D Server"))
							$metrics.push(This.metric("datastore.type"; "Host datastore type"; "text"; ""; "static"; $info.type))
						End if
					End if
					If ($metrics.length=0)
						$metrics.push(This.unavailable("datastore.type"; "Host datastore type"; "text"; ""; "static"; "error"; "Invalid datastore type"))
					End if
					$metrics.push(This.metric("datastore.networked"; "Host datastore networked"; "boolean"; ""; "static"; $info.networked))
					If (Value type($data.classes)=Is collection)
						$status:="available"
						If (($data.classes.length>512) | ($data.limitExceeded=True))
							$status:="error"
							$reason:="Dataclass metadata limit exceeded (512)"
						Else
							For each ($entry; $data.classes)
								If (Value type($entry)#Is object)
									$status:="error"
									$reason:="Invalid dataclass metadata"
									break
								End if
								If (Value type($entry.exposed)#Is boolean)
									$status:="error"
									$reason:="Invalid dataclass exposure"
									break
								End if
								If ($entry.exposed)
									$exposed+=1
								End if
							End for each
						End if
					Else
						$reason:="Missing dataclass metadata"
					End if
					If (($metrics[0].availability#"available") | ($metrics[1].availability#"available"))
						$status:="error"
						$reason:="Invalid datastore information"
					End if
				Else
					$reason:="Invalid datastore information"
				End if
		End case
	End if
	For each ($field; New collection("type"; "networked"; "classes"; "exposed"; "unexposed"))
		$type:="number"
		$unit:="dataclasses"
		$label:="Mapped dataclasses"
		Case of
			: ($field="type")
				$type:="text"
				$unit:=""
				$label:="Host datastore type"
			: ($field="networked")
				$type:="boolean"
				$unit:=""
				$label:="Host datastore networked"
			: ($field="exposed")
				$label:="REST-exposed dataclasses"
			: ($field="unexposed")
				$label:="REST-unexposed dataclasses"
		End case
		If ($metrics.length>=2)
			If (($field="type") | ($field="networked"))
				continue
			End if
		End if
		If ($status="available")
			Case of
				: ($field="classes")
					$metrics.push(This.metric("datastore."+$field; $label; $type; $unit; "static"; $data.classes.length))
				: ($field="exposed")
					$metrics.push(This.metric("datastore."+$field; $label; $type; $unit; "static"; $exposed))
				: ($field="unexposed")
					$metrics.push(This.metric("datastore."+$field; $label; $type; $unit; "static"; $data.classes.length-$exposed))
			End case
		Else
			$metrics.push(This.unavailable("datastore."+$field; $label; $type; $unit; "static"; $status; $reason))
		End if
	End for each

Function licenseUsage()->$metrics : Collection
	If (Application type=4D Server)
		$metrics:=This._licenseUsageMetrics(This.read("licenseUsage"))
	Else
		$metrics:=This._licenseUsageMetrics(New object("ok"; True; "data"; Null))
	End if

Function backup()->$metrics : Collection
	var $now : Real
	var $context; $read : Object
	$now:=Milliseconds
	If (This.backupMetrics#Null)
		If (($now>=This.backupReadAt) & ($now-This.backupReadAt<60000))
			$metrics:=This.backupMetrics.copy()
			return
		End if
	End if
	$read:=New object("availability"; "unsupported")
	If (Not(This.remote))
		$context:=This.read("backupContext")
		If (Not($context.ok))
			$read.availability:="error"
		Else
			If (Value type($context.data)=Is object)
				If ((Value type($context.data.type)=Is text) & (Value type($context.data.networked)=Is boolean))
					If (($context.data.type="4D") & Not($context.data.networked))
						// Main ds eligibility does not establish BACKUP INFO's data-file scope.
						$read.scopeUnverified:=True
					End if
				Else
					$read.availability:="error"
				End if
			Else
				If ($context.data#Null)
					$read.availability:="error"
				End if
			End if
		End if
	End if
	This.backupMetrics:=This._backupMetrics($read)
	This.backupMetrics.push(This.metric("backup.observedAt"; "Backup eligibility checked (UTC, 60s cache)"; "text"; ""; "static"; Timestamp))
	This.backupReadAt:=Milliseconds
	$metrics:=This.backupMetrics.copy()

Function _backupDate($id : Text; $label : Text; $read : Object)->$metric : Object
	var $data : Object
	$metric:=This.unavailable($id; $label; "text"; ""; "static"; "error"; "Backup date/time read failed or invalid")
	If (Value type($read)#Is object)
		return
	End if
	If (Value type($read.ok)#Is boolean)
		return
	End if
	If (Not($read.ok))
		return
	End if
	If (Value type($read.data)#Is object)
		return
	End if
	$data:=$read.data
	If (Value type($data.local)#Is text)
		return
	End if
	If ($data.local="")
		$metric:=This.unavailable($id; $label; "text"; ""; "static"; "missing"; "No backup date reported; history or schedule is unknown")
		return
	End if
	If (Not(This._backupTimestampValid($data.local; False)))
		return
	End if
	$metric:=This.metric($id; $label; "text"; ""; "static"; $data.local)

Function _backupTimestampValid($value : Variant; $utc : Boolean)->$valid : Boolean
	var $date : Date
	var $previous; $pattern : Text
	var CLI_LastErrors : Collection
	$valid:=False
	If (Value type($value)#Is text)
		return
	End if
	$pattern:="^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]"
	If ($utc)
		$pattern+="\\.[0-9]{3}Z"
	End if
	If (Not(Match regex($pattern+"$"; $value)))
		return
	End if
	$previous:=Method called on error(ek local)
	CLI_LastErrors:=Null
	ON ERR CALL("_CaptureError"; ek local)
	// Date requires the full ISO date/time form to avoid regional parsing.
	$date:=Date(Substring($value; 1; 19))
	If ($date#!0000-00-00!)
		$valid:=(Substring(String($date; ISO date); 1; 10)=Substring($value; 1; 10))
	End if
	ON ERR CALL($previous; ek local)
	If (CLI_LastErrors#Null)
		$valid:=False
	End if
	CLI_LastErrors:=Null

Function _backupIntegerValid($value : Variant; $minimum : Real)->$valid : Boolean
	$valid:=False
	If ((Value type($value)#Is real) & (Value type($value)#Is longint))
		return
	End if
	If (Not(($value>=$minimum) & ($value<=2147483647)))
		return
	End if
	$valid:=(Int($value)=$value)

Function _backupMetrics($read : Object)->$metrics : Collection
	var $last; $next; $information; $statusRead; $data; $metric : Object
	var $history; $beginValid : Boolean
	var $status; $reason; $field; $type; $unit; $label : Text
	$metrics:=New collection
	$data:=New object
	If (Value type($read)#Is object)
		$read:=New object("availability"; "error")
	End if
	If ($read.availability#"available")
		$status:=$read.availability
		$reason:="Backup metadata requires an eligible local main datastore; remote or dataless host unsupported"
		If ($read.scopeUnverified=True)
			$reason:="BACKUP INFO component-to-host data-file scope is unverified; host backup metadata unsupported"
		End if
		If ($status#"unsupported")
			$status:="error"
			$reason:="Backup datastore eligibility read failed or invalid"
		End if
	Else
		$last:=This._backupDate("backup.lastAt"; "Last backup (host-local)"; $read.last)
		$next:=This._backupDate("backup.nextAt"; "Next scheduled backup (host-local)"; $read.next)
		$metrics.push($last; $next)
		$information:=New object("ok"; False)
		$statusRead:=New object("ok"; False)
		If (Value type($read.information)=Is object)
			If (Value type($read.information.ok)=Is boolean)
				$information:=$read.information
			End if
		End if
		If (Value type($read.status)=Is object)
			If (Value type($read.status.ok)=Is boolean)
				$statusRead:=$read.status
			End if
		End if
		$beginValid:=False
		If ($information.ok)
			If (Value type($information.data)=Is object)
				$data:=$information.data
				$beginValid:=This._backupTimestampValid($data.begin; True)
			End if
		End if
		$history:=($last.availability="available") | $beginValid
		$status:="missing"
		$reason:="No recorded backup evidence; status and duration are unknown"
		If (Not($history))
			If (($last.availability="error") | Not($information.ok) | (Value type($information.data)#Is object))
				$status:="error"
				$reason:="Backup history could not be established"
			End if
		End if
	End if
	For each ($field; New collection("lastAt"; "nextAt"; "statusCode"; "duration"; "beginUTC"))
		$type:="text"
		$unit:=""
		Case of
			: ($field="lastAt")
				$label:="Last backup (host-local)"
			: ($field="nextAt")
				$label:="Next scheduled backup (host-local)"
			: ($field="statusCode")
				$label:="Last backup status code (uninterpreted)"
				$type:="number"
			: ($field="duration")
				$label:="Last backup duration"
				$type:="number"
				$unit:="ms"
			: ($field="beginUTC")
				$label:="Last backup begin (UTC)"
		End case
		If ($read.availability="available")
			If (($field="lastAt") | ($field="nextAt"))
				continue
			End if
		End if
		$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; $status; $reason)
		If ($read.availability="available")
			Case of
				: (($field="statusCode") & Not($statusRead.ok))
					$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; "error"; "Backup numeric metadata read failed or invalid")
				: (($field="duration") & Not($information.ok))
					$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; "error"; "Backup numeric metadata read failed or invalid")
				: ($field="beginUTC")
					$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; "error"; "Backup begin timestamp read failed or invalid")
					If ($beginValid)
						$metric:=This.metric("backup."+$field; $label; $type; $unit; "static"; $data.begin)
					Else
						If ($information.ok)
							If (Value type($data.begin)=Is text)
								If ($data.begin="")
									$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; "missing"; "No backup begin timestamp reported")
								End if
							End if
						End if
					End if
				: ($history)
					$metric:=This.unavailable("backup."+$field; $label; $type; $unit; "static"; "error"; "Backup numeric metadata read failed or invalid")
					If ($field="statusCode")
						If ($statusRead.ok)
							If (Value type($statusRead.data)=Is object)
								If (This._backupIntegerValid($statusRead.data.code; -2147483648))
									$metric:=This.metric("backup."+$field; $label; $type; $unit; "static"; $statusRead.data.code)
								End if
							End if
						End if
					Else
						If ($information.ok)
							If (This._backupIntegerValid($data.duration; 0))
								$metric:=This.metric("backup."+$field; $label; $type; $unit; "static"; $data.duration)
							End if
						End if
					End if
			End case
		End if
		$metrics.push($metric)
	End for each

Function engine()->$metrics : Collection
	var $now : Real
	var $remote; $metric : Object
	$now:=Milliseconds
	$remote:=New object("ok"; True; "data"; Null; "remote"; True)
	If (This.encryptionMetrics=Null)
		This.encryptionReadAt:=$now-60000
	End if
	// encryptionStatus() allocates a per-table map: read it at most once per 60 seconds.
	If (($now<This.encryptionReadAt) | ($now-This.encryptionReadAt>=60000))
		If (This.remote)
			This.encryptionMetrics:=This._encryptionMetrics($remote)
		Else
			This.encryptionMetrics:=This._encryptionMetrics(This.read("encryption"))
		End if
		This.encryptionReadAt:=Milliseconds
	End if
	$metrics:=This.encryptionMetrics.copy()
	If (This.remote)
		$metrics.push(This._engineFlag("datastore.locked"; $remote))
		$metrics.push(This._engineFlag("datastore.adminProtected"; $remote))
	Else
		$metrics.push(This._engineFlag("datastore.locked"; This.read("locked")))
		$metrics.push(This._engineFlag("datastore.adminProtected"; This.read("adminProtected")))
	End if

Function _engineFlag($id : Text; $read : Variant)->$metric : Object
	var $label : Text
	$label:="Datastore write freeze (lock, backup or VSS)"
	If ($id="datastore.adminProtected")
		$label:="Data Explorer access disabled"
	End if
	$metric:=This.unavailable($id; $label; "boolean"; ""; "gauge"; "error"; "Datastore state read failed or invalid")
	If (Value type($read)#Is object)
		return
	End if
	If (Value type($read.ok)#Is boolean)
		return
	End if
	If (Not($read.ok))
		return
	End if
	If (Value type($read.remote)=Is boolean)
		If ($read.remote)
			$metric:=This.unavailable($id; $label; "boolean"; ""; "gauge"; "unsupported"; "Unavailable on a remote client; run a collector on the server")
			return
		End if
	End if
	Case of
		: (Value type($read.data)=Is boolean)
			$metric:=This.metric($id; $label; "boolean"; ""; "gauge"; $read.data)
		: ($read.data=Null)
			$metric:=This.unavailable($id; $label; "boolean"; ""; "gauge"; "unsupported"; "No datastore available in this host")
	End case

Function _encryptionMetrics($read : Variant)->$metrics : Collection
	var $data; $tables : Object
	var $entry : Variant
	var $status; $reason; $countStatus; $countReason; $name; $field : Text
	var $count; $encryptable; $encrypted : Integer
	$metrics:=New collection
	$status:="error"
	$reason:="Datastore encryption status failed"
	If (Value type($read)=Is object)
		If (Value type($read.ok)=Is boolean)
			If ($read.ok)
				Case of
					: ($read.remote=True)
						$status:="unsupported"
						$reason:="Unavailable on a remote client; run a collector on the server"
					: ($read.data=Null)
						$status:="unsupported"
						$reason:="No datastore available in this host"
					: (Value type($read.data)#Is object)
						$reason:="Invalid encryption status"
					Else
						$data:=$read.data
						$reason:="Invalid encryption status"
						If (Value type($data.isEncrypted)=Is boolean)
							If (Value type($data.keyProvided)=Is boolean)
								$status:="available"
							End if
						End if
				End case
			End if
		End if
	End if
	If ($status#"available")
		$metrics.push(This.unavailable("datastore.encrypted"; "Data file encrypted"; "boolean"; ""; "static"; $status; $reason))
		$metrics.push(This.unavailable("datastore.encryptionKeyProvided"; "Data encryption key provided"; "boolean"; ""; "static"; $status; $reason))
		$metrics.push(This.unavailable("datastore.encryptableTables"; "Encryptable tables"; "number"; "tables"; "static"; $status; $reason))
		$metrics.push(This.unavailable("datastore.encryptedTables"; "Encrypted tables"; "number"; "tables"; "static"; $status; $reason))
		return
	End if
	$metrics.push(This.metric("datastore.encrypted"; "Data file encrypted"; "boolean"; ""; "static"; $data.isEncrypted))
	If ($data.isEncrypted)
		$metrics.push(This.metric("datastore.encryptionKeyProvided"; "Data encryption key provided"; "boolean"; ""; "static"; $data.keyProvided))
	Else
		$metrics.push(This.unavailable("datastore.encryptionKeyProvided"; "Data encryption key provided"; "boolean"; ""; "static"; "unsupported"; "Data file is not encrypted; no data key applies"))
	End if
	// The map lists only encryptable or encrypted tables. Names and numbers never leave this loop.
	$countStatus:="available"
	If (Value type($data.tables)#Is object)
		$countStatus:="error"
		$countReason:="Invalid encryption table map"
	Else
		$tables:=$data.tables
		For each ($name; $tables)
			$count+=1
			If ($count>512)
				$countStatus:="error"
				$countReason:="Encryption table limit exceeded (512)"
				break
			End if
			$entry:=$tables[$name]
			If (Value type($entry)#Is object)
				$countStatus:="error"
				$countReason:="Invalid encryption table entry"
				break
			End if
			If ((Value type($entry.isEncryptable)#Is boolean) | (Value type($entry.isEncrypted)#Is boolean))
				$countStatus:="error"
				$countReason:="Invalid encryption table entry"
				break
			End if
			If ($entry.isEncryptable)
				$encryptable+=1
			End if
			If ($entry.isEncrypted)
				$encrypted+=1
			End if
		End for each
	End if
	For each ($field; New collection("encryptableTables"; "encryptedTables"))
		$name:="Encryptable tables"
		$count:=$encryptable
		If ($field="encryptedTables")
			$name:="Encrypted tables"
			$count:=$encrypted
		End if
		If ($countStatus="available")
			$metrics.push(This.metric("datastore."+$field; $name; "number"; "tables"; "static"; $count))
		Else
			$metrics.push(This.unavailable("datastore."+$field; $name; "number"; "tables"; "static"; $countStatus; $countReason))
		End if
	End for each

Function _webMetrics($read : Variant)->$metrics : Collection
	var $data : Object
	var $value : Variant
	var $status; $reason; $field; $id; $label; $type; $unit; $kind; $version : Text
	var $valid : Boolean
	$metrics:=New collection
	$status:="error"
	$reason:="Host web server read failed"
	If (Value type($read)=Is object)
		If (Value type($read.unimplemented)=Is boolean)
			If ($read.unimplemented)
				$status:="unsupported"
				$reason:="This 4D runtime does not implement WEB Server (for example tool4d)"
			End if
		End if
		If (Value type($read.ok)=Is boolean)
			If ($read.ok)
				Case of
					: ($read.data=Null)
						$status:="unsupported"
						$reason:="No host web server object"
					: (Value type($read.data)#Is object)
						$reason:="Invalid host web server object"
					Else
						$status:="available"
						$data:=$read.data
				End case
			End if
		End if
	End if
	// Closed allowlist: no paths, addresses, ciphers, cookies, CORS, handlers, rules or access key.
	For each ($field; New collection("isRunning"; "HTTPEnabled"; "HTTPPort"; "HTTPSEnabled"; "HTTPSPort"; "HSTSEnabled"; "HSTSMaxAge"; "minTLSVersion"; "perfectForwardSecrecy"; "openSSLVersion"))
		$type:="boolean"
		$unit:=""
		$kind:="static"
		Case of
			: ($field="isRunning")
				$id:="web.running"
				$label:="Host web server running"
				$kind:="gauge"
			: ($field="HTTPEnabled")
				$id:="web.httpEnabled"
				$label:="HTTP enabled (current setting)"
			: ($field="HTTPPort")
				$id:="web.httpPort"
				$label:="HTTP port (current setting)"
				$type:="number"
				$unit:="port"
			: ($field="HTTPSEnabled")
				$id:="web.httpsEnabled"
				$label:="HTTPS enabled (current setting)"
			: ($field="HTTPSPort")
				$id:="web.httpsPort"
				$label:="HTTPS port (current setting)"
				$type:="number"
				$unit:="port"
			: ($field="HSTSEnabled")
				$id:="web.hstsEnabled"
				$label:="HSTS enabled (current setting)"
			: ($field="HSTSMaxAge")
				$id:="web.hstsMaxAge"
				$label:="HSTS max age (current setting)"
				$type:="number"
				$unit:="s"
			: ($field="minTLSVersion")
				$id:="web.minTLSVersion"
				$label:="Minimum TLS version (current setting)"
				$type:="text"
			: ($field="perfectForwardSecrecy")
				$id:="web.perfectForwardSecrecy"
				$label:="Perfect forward secrecy available"
			: ($field="openSSLVersion")
				$id:="web.openSSLVersion"
				$label:="OpenSSL library version"
				$type:="text"
		End case
		If ($status#"available")
			$metrics.push(This.unavailable($id; $label; $type; $unit; $kind; $status; $reason))
			continue
		End if
		$value:=$data[$field]
		$valid:=False
		Case of
			: ($type="boolean")
				$valid:=(Value type($value)=Is boolean)
			: ($type="number")
				If ((Value type($value)=Is real) | (Value type($value)=Is longint))
					If ($unit="port")
						$valid:=(($value>=1) & ($value<=65535))
					Else
						$valid:=(($value>=0) & ($value<=2147483647))
					End if
					If ($valid)
						$valid:=(Int($value)=$value)
					End if
				End if
			: ($field="minTLSVersion")
				// Setting enum 1..4; this is the configured floor, not a negotiated protocol.
				If ((Value type($value)=Is real) | (Value type($value)=Is longint))
					$version:=""
					Case of
						: ($value=1)
							$version:="TLS 1.0"
						: ($value=2)
							$version:="TLS 1.1"
						: ($value=3)
							$version:="TLS 1.2"
						: ($value=4)
							$version:="TLS 1.3"
					End case
					$valid:=($version#"")
					$value:=$version
				End if
			: ($field="openSSLVersion")
				If (Value type($value)=Is text)
					$valid:=Match regex("^[A-Za-z0-9 ._()+-]{1,64}$"; $value)
				End if
		End case
		If ($valid)
			$metrics.push(This.metric($id; $label; $type; $unit; $kind; $value))
		Else
			$metrics.push(This.unavailable($id; $label; $type; $unit; $kind; "error"; "Invalid host web server value"))
		End if
	End for each

Function _licenseUsageMetrics($read : Object)->$metrics : Collection
	var $entries; $ids : Collection
	var $entry : Variant
	var $products; $names : Object
	var $status; $reason; $id; $name; $metricId : Text
	var $count : Integer
	$products:=New object
	$status:="error"
	$reason:="License usage failed"
	If ($read.ok)
		If (Value type($read.data)=Is collection)
			$entries:=$read.data
			$status:="available"
			For each ($entry; $entries)
				If (Value type($entry)#Is object)
					$status:="error"
					$reason:="Invalid license usage entry"
					break
				End if
				If ((Value type($entry.productId)#Is longint) & (Value type($entry.productId)#Is real))
					$status:="error"
					$reason:="Invalid license product identifier"
					break
				End if
				If (($entry.productId<0) | ($entry.productId>9007199254740991))
					$status:="error"
					$reason:="Invalid license product identifier"
					break
				End if
				If (Int($entry.productId)#$entry.productId)
					$status:="error"
					$reason:="Invalid license product identifier"
					break
				End if
				$id:=String($entry.productId; 10)
				$name:="Product "+$id
				If (Value type($entry.productName)=Is text)
					If ($entry.productName#"")
						$name:=Substring($entry.productName; 1; 24)
					End if
				End if
				If ($products[$id]=Null)
					$products[$id]:=New object("name"; $name; "count"; 0)
				End if
				$products[$id].count+=1
			End for each
			If ($status="available")
				$names:=OB Copy(This.licenseProducts)
				For each ($id; OB Keys($products))
					$names[$id]:=$products[$id].name
				End for each
				$ids:=OB Keys($names)
				If ($ids.length>64)
					$status:="error"
					$reason:="License product tracking limit exceeded (64)"
				Else
					This.licenseProducts:=$names
				End if
			End if
		Else
			If ($read.data=Null)
				$status:="unsupported"
				$reason:="License usage is available only on 4D Server"
			Else
				$reason:="License usage did not return a Collection"
			End if
		End if
	End if
	$metrics:=New collection
	If ($status="available")
		$metrics.push(This.metric("license.usage.records"; "Retained license records"; "number"; "records"; "gauge"; $entries.length))
	Else
		$metrics.push(This.unavailable("license.usage.records"; "Retained license records"; "number"; "records"; "gauge"; $status; $reason))
	End if
	For each ($id; OB Keys(This.licenseProducts))
		$metricId:="license.usage.product."+$id
		$name:=This.licenseProducts[$id]+": retained records"
		If ($status="available")
			$count:=0
			If ($products[$id]#Null)
				$count:=$products[$id].count
			End if
			$metrics.push(This.metric($metricId; $name; "number"; "records"; "gauge"; $count))
		Else
			$metrics.push(This.unavailable($metricId; $name; "number"; "records"; "gauge"; $status; $reason))
		End if
	End for each

Function snapshot()->$snapshot : Object
	var $metrics; $processes; $sessions : Collection
	var $read; $data; $entry; $detail; $entity : Object
	var $field; $status; $reason : Text
	var $previous; $id : Text
	var $seen : Object
	var CLI_LastErrors : Collection
	This.sampleCount+=1
	$metrics:=This.staticMetrics.copy()
	For each ($entry; This.backup())
		$metrics.push($entry)
	End for each
	For each ($entry; This.engine())
		$metrics.push($entry)
	End for each
	For each ($entry; This._webMetrics(This.read("web")))
		$metrics.push($entry)
	End for each
	For each ($entry; This.licenseUsage())
		$metrics.push($entry)
	End for each
	$processes:=New collection
	$sessions:=New collection
	$read:=This.read("application")
	For each ($field; New collection("uptime"; "cpuUsage"; "networkInputThroughput"; "networkOutputThroughput"))
		$status:="error"
		$reason:="Application info failed"
		If ($read.ok)
			If (Is Windows & (This.sampleCount=1) & ($field#"uptime"))
				$status:="missing"
				$reason:="Windows counter warming up; wait for another sample"
			Else
				$data:=$read.data
				Case of
					: ($field="uptime")
						$metrics.push(This.metric("app."+$field; "4D uptime"; "number"; "s"; "gauge"; $data[$field]))
					: ($field="cpuUsage")
						$metrics.push(This.metric("app."+$field; "4D CPU (OS-specific)"; "number"; "%"; "gauge"; $data[$field]))
					Else
						$metrics.push(This.metric("app."+$field; $field+" (machine)"; "number"; "B/s"; "gauge"; $data[$field]))
				End case
				continue
			End if
		End if
		$metrics.push(This.unavailable("app."+$field; $field; "number"; ""; "gauge"; $status; $reason))
	End for each
	$metrics.push(This.metric("database.locked"; "Data file write protected"; "boolean"; ""; "gauge"; Is data file locked))
	$status:="unsupported"
	$reason:="Unavailable on a remote client; run a collector on the server"
	If (Not(This.remote))
		$read:=This.read("cache")
		$status:="error"
		$reason:="Cache info failed"
	End if
	For each ($field; New collection("maxMem"; "usedMem"))
		If (Not(This.remote))
			If ($read.ok)
				$data:=$read.data
				$metrics.push(This.metric("cache."+$field; "Cache "+$field; "number"; "bytes"; "gauge"; $data[$field]))
				continue
			End if
		End if
		$metrics.push(This.unavailable("cache."+$field; "Cache "+$field; "number"; "bytes"; "gauge"; $status; $reason))
	End for each
	If (Not(This.remote))
		$read:=This.read("measures")
		$status:="error"
		$reason:="Database measures failed"
	End if
	For each ($field; New collection("diskReadBytes"; "diskWriteBytes"; "cacheReadBytes"; "cacheMissBytes"; "diskReadCount"; "diskWriteCount"; "cacheReadCount"; "cacheMissCount"))
		If (Not(This.remote))
			If ($read.ok)
				$data:=$read.data
				$detail:=$data.DB
				If ($detail#Null)
					$detail:=$detail[$field]
					If ($detail#Null)
						$metrics.push(This.metric("database."+$field; $field; "number"; ""; "counter"; $detail.value))
						continue
					End if
				End if
				$metrics.push(This.unavailable("database."+$field; $field; "number"; ""; "counter"; "missing"; "No events reported; absence is not zero"))
				continue
			End if
		End if
		$metrics.push(This.unavailable("database."+$field; $field; "number"; ""; "counter"; $status; $reason))
	End for each
	$read:=This.read("activity")
	If ($read.ok)
		$data:=$read.data
		If (Value type($data.processes)=Is collection)
			$seen:=New object
			For each ($entry; $data.processes)
				If ($processes.length>=512)
					break
				End if
				// Internal 4D processes all report ID 0 (and number 0): key them by OS thread instead.
				$id:=""
				If (Num($entry.ID)>0)
					$id:="p:"+String(Num($entry.ID))
				Else
					If (Value type($entry.systemID)=Is text)
						$id:="t:"+$entry.systemID
					End if
				End if
				If (Not(Match regex("^[A-Za-z0-9_.:-]{1,96}$"; $id)) | ($seen[$id]#Null))
					continue
				End if
				$seen[$id]:=True
				$detail:=$entry
				// Process info does not reach every internal process: retain the activity entry.
				If (Value type($entry.number)=Is longint)
					$previous:=Method called on error(ek local)
					CLI_LastErrors:=Null
					ON ERR CALL("_CaptureError"; ek local)
					$detail:=Process info($entry.number)
					ON ERR CALL($previous; ek local)
					If ((CLI_LastErrors#Null) | ($detail=Null))
						$detail:=$entry
					End if
					CLI_LastErrors:=Null
				End if
				$entity:=New object("id"; $id; "type"; Substring(String($detail.type); 1; 64); "state"; Substring(String($detail.state); 1; 64))
				If ((Value type($detail.cpuUsage)=Is real) | (Value type($detail.cpuUsage)=Is longint))
					If (($detail.cpuUsage>=0) & ($detail.cpuUsage<=1))
						$entity.cpu:=$detail.cpuUsage
					End if
				End if
				$processes.push($entity)
			End for each
			$metrics.push(This.metric("process.count"; "Visible processes"; "number"; "processes"; "gauge"; $data.processes.length))
			$metrics.push(This.metric("process.truncated"; "Process list truncated"; "boolean"; ""; "gauge"; $data.processes.length>512))
		Else
			$metrics.push(This.unavailable("process.count"; "Visible processes"; "number"; "processes"; "gauge"; "unsupported"; "Process enumeration was not returned by this host"))
		End if
		If (Value type($data.sessions)=Is collection)
			$seen:=New object
			For each ($entry; $data.sessions)
				If ($sessions.length>=512)
					break
				End if
				$id:="s:"+String($entry.ID)
				If (Not(Match regex("^[A-Za-z0-9_.:-]{1,96}$"; $id)) | ($seen[$id]#Null) | ($id="s:"))
					continue
				End if
				$seen[$id]:=True
				$previous:=Method called on error(ek local)
				CLI_LastErrors:=Null
				ON ERR CALL("_CaptureError"; ek local)
				$detail:=Session info($entry.ID)
				ON ERR CALL($previous; ek local)
				If ((CLI_LastErrors#Null) | ($detail=Null))
					$detail:=$entry
				End if
				CLI_LastErrors:=Null
				$sessions.push(New object("id"; $id; "type"; Substring(String($detail.type); 1; 64); "state"; Substring(String($detail.state); 1; 64)))
			End for each
			$metrics.push(This.metric("session.count"; "Visible server sessions"; "number"; "sessions"; "gauge"; $data.sessions.length))
			$metrics.push(This.metric("session.truncated"; "Session list truncated"; "boolean"; ""; "gauge"; $data.sessions.length>512))
		Else
			$metrics.push(This.unavailable("session.count"; "Server sessions"; "number"; "sessions"; "gauge"; "unsupported"; "Session enumeration is server-only"))
		End if
	Else
		$metrics.push(This.unavailable("process.count"; "Visible processes"; "number"; "processes"; "gauge"; "error"; "Process activity failed"))
		$metrics.push(This.unavailable("session.count"; "Visible sessions"; "number"; "sessions"; "gauge"; "error"; "Process activity failed"))
	End if
	$snapshot:=New object("metrics"; $metrics; "processes"; $processes; "sessions"; $sessions)
