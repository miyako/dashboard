property info : Object
property staticMetrics : Collection
property sampleCount : Integer
property remote : Boolean

Class constructor
	var $system; $license; $read : Object
	var $role; $platform : Text
	This.sampleCount:=0
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

Function read($command : Text)->$result : Object
	var $previous : Text
	var $data : Object
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
		: ($command="cache")
			$data:=Cache info(New object("dbFilter"; "All"))
		: ($command="measures")
			$data:=Database measures(New object("withHistory"; False; "path"; New collection("DB.diskReadBytes"; "DB.diskWriteBytes"; "DB.cacheReadBytes"; "DB.cacheMissBytes"; "DB.diskReadCount"; "DB.diskWriteCount"; "DB.cacheReadCount"; "DB.cacheMissCount")))
		: ($command="activity")
			$data:=Process activity
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

Function snapshot()->$snapshot : Object
	var $metrics; $processes; $sessions : Collection
	var $read; $data; $entry; $detail; $entity : Object
	var $field; $status; $reason : Text
	var $previous : Text
	var CLI_LastErrors : Collection
	This.sampleCount+=1
	$metrics:=This.staticMetrics.copy()
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
