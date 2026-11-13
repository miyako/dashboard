property info : Object
property staticMetrics : Collection
property sampleCount : Integer
property remote : Boolean
property licenseProducts : Object
property backupMetrics : Collection
property backupReadAt : Real

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
	End case
	ON ERR CALL($previous; ek local)
	$result:=New object("ok"; CLI_LastErrors=Null; "data"; $data)
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
	$date:=Date(Substring($value; 1; 10))
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
	var $previous : Text
	var CLI_LastErrors : Collection
	This.sampleCount+=1
	$metrics:=This.staticMetrics.copy()
	For each ($entry; This.backup())
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
			For each ($entry; $data.processes)
				If ($processes.length>=512)
					break
				End if
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
				$entity:=New object("id"; "p:"+String($entry.ID); "type"; String($detail.type); "state"; String($detail.state))
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
			For each ($entry; $data.sessions)
				If ($sessions.length>=512)
					break
				End if
				$previous:=Method called on error(ek local)
				CLI_LastErrors:=Null
				ON ERR CALL("_CaptureError"; ek local)
				$detail:=Session info($entry.ID)
				ON ERR CALL($previous; ek local)
				If ((CLI_LastErrors#Null) | ($detail=Null))
					$detail:=$entry
				End if
				CLI_LastErrors:=Null
				$sessions.push(New object("id"; "s:"+$entry.ID; "type"; String($detail.type); "state"; String($detail.state)))
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
