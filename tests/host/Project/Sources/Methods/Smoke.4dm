//%attributes = {"invisible":true}
var $ignored : Integer
var $parameter; $name; $target : Text
var $folderPath : Text
var $request; $result; $report : Object
var $tool : cs.Dashboard.Dashboard
var $requestFile; $statusFile : 4D.File
var $renamedExecutable : 4D.File
var $cases : Collection
var $invalid : Variant
var HOST_StatusFile : 4D.File
var HOST_Phase : Text
var HOST_PreviousHandler : Text
var HOST_Report : Object
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
$statusFile.setText("{\"success\":false,\"phase\":\"starting\"}")
HOST_StatusFile:=$statusFile
HOST_Phase:="constructor"
HOST_PreviousHandler:=Method called on error(ek local)
ON ERR CALL("Host_error"; ek local)
$target:="macOS-universal"
If (Is Windows)
	$target:="Windows-x64"
End if
$tool:=cs.Dashboard.Dashboard.new($target)
$cases:=New collection("world"; "path with spaces"; "quote \" and \\ slash"; "line\nbreak"; "日本語"; "$() ; & % !")
$report:=New object("success"; True; "finished"; False; "cases"; New collection)
// Same object: a crash report then includes everything gathered so far.
HOST_Report:=$report
$report.compiled:=$tool._cli.compiled
HOST_Phase:="renamed executable"
If (Is Windows)
	$renamedExecutable:=File($request.executable; fk platform path)
Else
	$renamedExecutable:=File($request.executable; fk posix path)
End if
$report.renamedExecutable:=cs.Dashboard._Process.new().execute($renamedExecutable; New collection("--version"))
If (Not($report.renamedExecutable.ok))
	$report.success:=False
End if
HOST_Phase:="feature cases"
If ($request.expectCompiled#$report.compiled)
	$report.success:=False
End if
For each ($name; $cases)
	$result:=$tool.inspect($name)
	$report.cases.push($result)
	If (Not($result.ok))
		$report.success:=False
	Else
		If ($result.value.text#$name)
			$report.success:=False
		End if
	End if
End for each
$result:=$tool.inspect("")
$report.invalid:=$result
If ($result.ok | ($result.exitCode#2))
	$report.success:=False
End if
$result:=$tool.version()
$report.version:=$result
If (Not($result.ok))
	$report.success:=False
Else
	If ($result.value.version#"0.1.6")
		$report.success:=False
	End if
End if
HOST_Phase:="missing executable"
$result:=cs.Dashboard._CLI.new("missing-cli"; $target).execute(New collection("--version"))
$report.missing:=$result
If ($result.error.code#"missing_executable")
	$report.success:=False
End if
$result:=cs.Dashboard.Dashboard.new("unsupported-arm-target").version()
$report.unsupported:=$result
If ($result.error.code#"unsupported_architecture")
	$report.success:=False
End if
HOST_Phase:="launch failure"
$result:=cs.Dashboard._Process.new().execute($requestFile; New collection)
$report.launch:=$result
If ($result.error.code#"launch_failed")
	$report.success:=False
End if
HOST_Phase:="malformed protocol"
$result:=$tool._decode(New object("ok"; True; "stdout"; "not json"; "stderr"; ""; "exitCode"; 0); "message")
$report.protocol:=$result
If ($result.error.code#"invalid_protocol")
	$report.success:=False
End if
$report.protocolTypes:=New collection
For each ($name; New collection("{\"protocol\":true,\"message\":\"invalid\"}"; "{\"protocol\":false,\"message\":\"invalid\"}"))
	$result:=$tool._decode(New object("ok"; True; "stdout"; $name; "stderr"; ""; "exitCode"; 0); "message")
	$report.protocolTypes.push($result)
	If ($result.ok | ($result.error.code#"invalid_protocol"))
		$report.success:=False
	End if
End for each
$result:=$tool._decode(New object("ok"; True; "stdout"; "{\"protocol\":null,\"message\":\"invalid\"}"; "stderr"; ""; "exitCode"; 0); "message")
$report.protocolNull:=$result
If ($result.ok | ($result.error.code#"invalid_protocol"))
	$report.success:=False
End if
$report.protocolScalars:=New collection
For each ($name; New collection("true"; "false"; "null"; "1"; "[]"))
	$result:=$tool._decode(New object("ok"; True; "stdout"; $name; "stderr"; ""; "exitCode"; 0); "message")
	$report.protocolScalars.push($result)
	If ($result.ok | ($result.error.code#"invalid_protocol"))
		$report.success:=False
	End if
End for each
HOST_Phase:="File argument"
$result:=cs.Dashboard._CLI.new("dashboard"; $target).execute(New collection("inspect"; "--text"; $requestFile))
$report.fileArgument:=$result
If (Not($result.ok))
	$report.success:=False
Else
	If (JSON Parse($result.stdout).text#$parameter)
		$report.success:=False
	End if
End if
$report.rejectedArguments:=New collection
HOST_Phase:="scalar arguments"
For each ($invalid; New collection(123; 1.25; True; False; Null; Current date; Current time; New collection; New object))
	$result:=cs.Dashboard._Process.new().execute($requestFile; New collection($invalid))
	$report.rejectedArguments.push(New object("type"; Value type($invalid); "result"; $result))
	If ($result.ok | ($result.error.code#"invalid_argument"))
		$report.success:=False
	End if
End for each
$report.rejectedNul:=New collection
HOST_Phase:="NUL arguments"
For each ($name; New collection(Char(0)+"prefix"; "middle"+Char(0)+"suffix"; "trailing"+Char(0)))
	$result:=cs.Dashboard._Process.new().execute($requestFile; New collection($name))
	$report.rejectedNul.push($result)
	If ($result.ok | ($result.error.code#"invalid_argument"))
		$report.success:=False
	End if
End for each
$report.missingFile:=cs.Dashboard._Process.new().execute(Null; New collection)
$report.missingArguments:=cs.Dashboard._Process.new().execute($requestFile; Null)
If ($report.missingFile.ok | ($report.missingFile.error.code#"invalid_argument"))
	$report.success:=False
End if
If ($report.missingArguments.ok | ($report.missingArguments.error.code#"invalid_argument"))
	$report.success:=False
End if
HOST_Phase:="Folder argument"
$result:=cs.Dashboard._CLI.new("dashboard"; $target).execute(New collection("inspect"; "--text"; $requestFile.parent))
$report.folderArgument:=$result
$folderPath:=$requestFile.parent.path
If (Is Windows)
	$folderPath:=$requestFile.parent.platformPath
End if
If (Not($result.ok))
	$report.success:=False
Else
	If (JSON Parse($result.stdout).text#$folderPath)
		$report.success:=False
	End if
End if
HOST_Phase:="real collector"
var $entityList : Text
var $entitySeen; $entityItem : Object
$result:=$tool.collect()
$report.collector:=$result
If (Not($result.ok))
	$report.success:=False
Else
	If ($result.value.metrics.length<15)
		$report.success:=False
	End if
	// The CLI rejects a frame with a duplicate or malformed entity ID; 4D reports ID 0 for every internal process.
	For each ($entityList; New collection("processes"; "sessions"))
		$entitySeen:=New object
		For each ($entityItem; $result.value[$entityList])
			If (Not(Match regex("^[A-Za-z0-9_.:-]{1,96}$"; String($entityItem.id))) | ($entitySeen[String($entityItem.id)]#Null))
				$report.success:=False
				$report.invalidEntity:=$entityItem
			End if
			$entitySeen[String($entityItem.id)]:=True
		End for each
	End for each
End if
HOST_Phase:="license usage normalization"
var $collector : cs.Dashboard._DashboardCollector
var $licenseCases; $licenseCase : Object
var $licenseEntries; $normalized : Collection
var $measurement : Object
var $licenseCaseName : Text
var $productIndex : Integer
$collector:=cs.Dashboard._DashboardCollector.new()
HOST_Phase:="backup normalization"
var $backupCases; $backupRead; $backupCase; $backupPositive : Object
$backupPositive:=New object("availability"; "available"; \
	"last"; New object("ok"; True; "data"; New object("local"; String(!2026-11-14!; ISO date; ?00:00:00?))); \
	"next"; New object("ok"; True; "data"; New object("local"; String(!2026-11-15!; ISO date; ?00:00:00?))); \
	"status"; New object("ok"; True; "data"; New object("code"; 37; "text"; "/private/archive.4BK private-user")); \
	"information"; New object("ok"; True; "data"; New object("duration"; 1200; "begin"; "2026-11-13T15:00:00.123Z"; "path"; "/private/archive.4BK")))
$backupCases:=New object
// Separate mutable copies; no fixture can approve the native backup observation.
$backupCases.positive:=OB Copy($backupPositive)
$backupCases.zeroDuration:=OB Copy($backupPositive)
$backupCases.zeroDuration.information.data.duration:=0
$backupCases.noBegin:=OB Copy($backupCases.zeroDuration)
$backupCases.noBegin.information.data.begin:=""
$backupCases.noBegin.status.data.code:=0
$backupCases.beginOnly:=OB Copy($backupPositive)
$backupCases.beginOnly.last.data.local:=""
$backupCases.noHistory:=OB Copy($backupPositive)
$backupCases.noHistory.last.data.local:=""
$backupCases.noHistory.next.data.local:=""
$backupCases.noHistory.information.data.begin:=""
$backupCases.noHistory.information.data.duration:=0
$backupCases.noHistory.status.data.code:=0
$backupCases.failed:=OB Copy($backupPositive)
$backupCases.failed.last.ok:=False
$backupCases.failed.next.ok:=False
$backupCases.failed.status.ok:=False
$backupCases.failed.information.ok:=False
$backupCases.invalid:=OB Copy($backupPositive)
$backupCases.invalid.last.data.local:=False
$backupCases.invalid.next.data.local:="2026-11-14T24:00:00"
$backupCases.invalid.status.data.code:="0"
$backupCases.invalid.information.data.duration:=-1
$backupCases.invalid.information.data.begin:="/private/archive.4BK"
$backupCases.badCalendar:=OB Copy($backupPositive)
$backupCases.badCalendar.information.data.begin:="2026-02-31T15:00:00.123Z"
$backupCases.fraction:=OB Copy($backupPositive)
$backupCases.fraction.information.data.duration:=1.5
$backupCases.invalidNumeric:=OB Copy($backupPositive)
$backupCases.invalidNumeric.status.data.code:=True
$backupCases.invalidNumeric.information.data.duration:=2147483648
$backupCases.unsupported:=New object("availability"; "unsupported")
$backupCases.scopeUnverified:=New object("availability"; "unsupported"; "scopeUnverified"; True)
$backupCases.missing:=New object("availability"; "available")
$report.backup:=New object
$report.backup.calendarContext:=New object("shortDate"; String(!2026-11-14!); "bareDateValid"; Date("2026-11-14")=!2026-11-14!)
$report.backup.calendar:=New collection
var $calendarCase : Object
For each ($calendarCase; New collection(\
	New object("input"; "2026-11-14T00:00:00"; "utc"; False); \
	New object("input"; "2000-02-29T23:59:59"; "utc"; False); \
	New object("input"; "2026-12-31T23:59:59.999Z"; "utc"; True); \
	New object("input"; "1900-02-29T00:00:00"; "utc"; False); \
	New object("input"; "2000-02-30T00:00:00.000Z"; "utc"; True); \
	New object("input"; "2026-04-31T00:00:00"; "utc"; False)))
	$report.backup.calendar.push(New object("input"; $calendarCase.input; "utc"; $calendarCase.utc; "valid"; $collector._backupTimestampValid($calendarCase.input; $calendarCase.utc)))
End for each
For each ($name; OB Keys($backupCases))
	$backupCase:=New object
	For each ($measurement; $collector._backupMetrics($backupCases[$name]))
		$backupCase[$measurement.id]:=$measurement
	End for each
	$report.backup[$name]:=$backupCase
End for each
$report.backup.native:=New object
For each ($measurement; $collector.backup())
	$report.backup.native[$measurement.id]:=$measurement
End for each
var $backupCachedAt : Real
$backupCachedAt:=$collector.backupReadAt
$result:=$collector.snapshot()
$report.backup.cached:=($collector.backupReadAt=$backupCachedAt)
$collector.backupReadAt:=Milliseconds-60000
$backupCachedAt:=$collector.backupReadAt
$normalized:=$collector.backup()
$report.backup.refreshed:=($collector.backupReadAt-$backupCachedAt>=60000)
HOST_Phase:="datastore normalization"
var $metadataCases; $metadataCase : Object
var $metadataEntries : Collection
var $metadataIndex : Integer
$metadataCases:=New object(\
	"populated"; New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False; "localID"; "private-id"; "connection"; New object("hostname"; "private-ip"; "user"; "private-user")); "classes"; New collection(New object("exposed"; True; "name"; "private-class"; "primaryKey"; "private-key"; "tableNumber"; 999); New object("exposed"; False)))); \
	"empty"; New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; New collection)); \
	"failed"; New object("ok"; False); \
	"absent"; New object("ok"; True; "data"; Null); \
	"invalid"; New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; New collection(New object("exposed"; True); New object("exposed"; "true")))); \
	"invalidInfo"; New object("ok"; True; "data"; New object("info"; False)); \
	"invalidType"; New object("ok"; True; "data"; New object("info"; New object("type"; "private-type"; "networked"; Null); "classes"; New collection)); \
	"invalidEntry"; New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; New collection(False))); \
	"truncated"; New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; New collection; "limitExceeded"; True)))
$metadataEntries:=New collection
For ($metadataIndex; 1; 512)
	$metadataEntries.push(New object("exposed"; False))
End for
$metadataCases.boundary:=New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; $metadataEntries.copy()))
$metadataEntries.push(New object("exposed"; True))
$metadataCases.overflow:=New object("ok"; True; "data"; New object("info"; New object("type"; "4D"; "networked"; False); "classes"; $metadataEntries))
$report.datastore:=New object
For each ($name; OB Keys($metadataCases))
	$metadataCase:=New object
	$normalized:=$collector._datastoreMetrics($metadataCases[$name])
	If ($normalized.length#5)
		$report.success:=False
	End if
	For each ($measurement; $normalized)
		$metadataCase[$measurement.id]:=$measurement
	End for each
	$report.datastore[$name]:=$metadataCase
End for each
$report.datastore.cached:=(JSON Stringify($collector.staticMetrics)=JSON Stringify($collector.snapshot().metrics.slice(0; $collector.staticMetrics.length)))
HOST_Phase:="engine posture normalization"
var $engineCases; $engineTables; $engineCase : Object
var $engineIndex : Integer
var $engineCachedAt : Real
$engineTables:=New object(\
	"PrivateSecret"; New object("name"; "private-table"; "num"; 999; "isEncryptable"; True; "isEncrypted"; True); \
	"PrivatePending"; New object("name"; "private-pending"; "num"; 998; "isEncryptable"; True; "isEncrypted"; False))
$engineCases:=New object(\
	"plain"; New object("ok"; True; "data"; New object("isEncrypted"; False; "keyProvided"; False; "tables"; New object)); \
	"encrypted"; New object("ok"; True; "data"; New object("isEncrypted"; True; "keyProvided"; True; "tables"; $engineTables; "dataKey"; "private-key")); \
	"keyMissing"; New object("ok"; True; "data"; New object("isEncrypted"; True; "keyProvided"; False; "tables"; New object)); \
	"failed"; New object("ok"; False); \
	"absent"; New object("ok"; True; "data"; Null); \
	"remote"; New object("ok"; True; "data"; Null; "remote"; True); \
	"invalid"; New object("ok"; True; "data"; New object("isEncrypted"; "true"; "keyProvided"; False; "tables"; New object)); \
	"invalidMap"; New object("ok"; True; "data"; New object("isEncrypted"; False; "keyProvided"; False; "tables"; New collection)); \
	"invalidEntry"; New object("ok"; True; "data"; New object("isEncrypted"; False; "keyProvided"; False; "tables"; New object("PrivateTable"; New object("isEncryptable"; "yes"; "isEncrypted"; False)))))
$engineTables:=New object
For ($engineIndex; 1; 512)
	$engineTables["T"+String($engineIndex)]:=New object("isEncryptable"; True; "isEncrypted"; ($engineIndex%2)=0)
End for
$engineCases.boundary:=New object("ok"; True; "data"; New object("isEncrypted"; True; "keyProvided"; True; "tables"; OB Copy($engineTables)))
$engineTables.T513:=New object("isEncryptable"; True; "isEncrypted"; True)
$engineCases.overflow:=New object("ok"; True; "data"; New object("isEncrypted"; True; "keyProvided"; True; "tables"; $engineTables))
$report.engine:=New object("encryption"; New object; "flags"; New object)
For each ($name; OB Keys($engineCases))
	$engineCase:=New object
	$normalized:=$collector._encryptionMetrics($engineCases[$name])
	If ($normalized.length#4)
		$report.success:=False
	End if
	For each ($measurement; $normalized)
		$engineCase[$measurement.id]:=$measurement
	End for each
	$report.engine.encryption[$name]:=$engineCase
End for each
$engineCases:=New object(\
	"true"; New object("ok"; True; "data"; True); \
	"false"; New object("ok"; True; "data"; False); \
	"failed"; New object("ok"; False; "data"; True); \
	"absent"; New object("ok"; True; "data"; Null); \
	"remote"; New object("ok"; True; "data"; Null; "remote"; True); \
	"invalid"; New object("ok"; True; "data"; "true"); \
	"malformed"; "private-read")
For each ($name; OB Keys($engineCases))
	$report.engine.flags[$name]:=$collector._engineFlag("datastore.locked"; $engineCases[$name])
End for each
$report.engine.adminLabel:=$collector._engineFlag("datastore.adminProtected"; New object("ok"; True; "data"; False)).label
// Live reads on this host: record what the engine actually reports, whatever its availability.
$report.engine.live:=New object
For each ($measurement; $collector.engine())
	$report.engine.live[$measurement.id]:=$measurement
End for each
$engineCachedAt:=$collector.encryptionReadAt
$normalized:=$collector.engine()
$report.engine.cached:=($collector.encryptionReadAt=$engineCachedAt)
$collector.encryptionReadAt:=Milliseconds-60000
$engineCachedAt:=$collector.encryptionReadAt
$normalized:=$collector.engine()
$report.engine.refreshed:=($collector.encryptionReadAt-$engineCachedAt>=60000)
$report.engine.inSnapshot:=($collector.snapshot().metrics.query("id = :1"; "datastore.locked").length=1)
HOST_Phase:="web server normalization"
var $webCases; $webValid; $webCase; $webHost; $webRead : Object
$webValid:=New object("isRunning"; False; "HTTPEnabled"; True; "HTTPPort"; 8080; "HTTPSEnabled"; False; "HTTPSPort"; 8443; "HSTSEnabled"; False; "HSTSMaxAge"; 63072000; "minTLSVersion"; 3; "perfectForwardSecrecy"; True; "openSSLVersion"; "OpenSSL 3.5.1 1 Jul 2025"; \
	"rootFolder"; "/private/web/"; "certificateFolder"; "/private/cert/"; "IPAddressToListen"; "192.0.2.1"; "cipherSuite"; "private-cipher"; "accessKeyDefined"; True; "sessionCookieName"; "private-cookie"; "CORSSettings"; New collection(New object("host"; "private.example")))
$webCases:=New object(\
	"populated"; New object("ok"; True; "data"; $webValid); \
	"failed"; New object("ok"; False; "data"; $webValid); \
	"absent"; New object("ok"; True; "data"; Null); \
	"invalidObject"; New object("ok"; True; "data"; "private-web"); \
	"invalidValues"; New object("ok"; True; "data"; New object("isRunning"; "true"; "HTTPEnabled"; True; "HTTPPort"; 0; "HTTPSEnabled"; Null; "HTTPSPort"; 70000; "HSTSEnabled"; True; "HSTSMaxAge"; -1; "minTLSVersion"; 5; "perfectForwardSecrecy"; 1; "openSSLVersion"; "/private/lib/libssl")); \
	"tls10"; New object("ok"; True; "data"; New object("minTLSVersion"; 1)); \
	"tls11"; New object("ok"; True; "data"; New object("minTLSVersion"; 2)); \
	"tls13"; New object("ok"; True; "data"; New object("minTLSVersion"; 4)))
$report.web:=New object("cases"; New object)
For each ($name; OB Keys($webCases))
	$webCase:=New object
	$normalized:=$collector._webMetrics($webCases[$name])
	If ($normalized.length#10)
		$report.success:=False
	End if
	For each ($measurement; $normalized)
		$webCase[$measurement.id]:=$measurement
	End for each
	$report.web.cases[$name]:=$webCase
End for each
$report.web.cases.unimplemented:=New object
For each ($measurement; $collector._webMetrics(New object("ok"; False; "unimplemented"; True)))
	$report.web.cases.unimplemented[$measurement.id]:=$measurement
End for each
// Targeting: the collector's option-2 read must be this host's server, not the component's own.
$webRead:=$collector.read("web")
$report.web.read:=New object("ok"; $webRead.ok; "unimplemented"; $webRead.unimplemented=True)
If (Application type=tool4d)
	// tool4d implements no WEB Server command; host targeting needs a full 4D runtime.
	$report.web.targeting:=New object("status"; "not_run"; "reason"; "tool4d does not implement WEB Server")
Else
	$webHost:=WEB Server
	$report.web.targeting:=New object("status"; "passed"; "ok"; $webRead.ok; "hostRootText"; Value type($webHost.rootFolder)=Is text; "collectorRootText"; False; "matchesHost"; False; "notComponent"; False)
End if
If ($webRead.ok & (Application type#tool4d))
	If (Value type($webRead.data)=Is object)
		If (Value type($webRead.data.rootFolder)=Is text)
			$report.web.targeting.collectorRootText:=True
			$report.web.targeting.matchesHost:=($webRead.data.rootFolder=$webHost.rootFolder)
			$report.web.targeting.notComponent:=(Position("dashboard.4dbase"; $webRead.data.rootFolder)=0)
		End if
	End if
End if
$report.web.live:=New object
For each ($measurement; $collector._webMetrics($webRead))
	$report.web.live[$measurement.id]:=$measurement
End for each
$report.web.inSnapshot:=($collector.snapshot().metrics.query("id = :1"; "web.running").length=1)
HOST_Phase:="database parameter normalization"
var $parameterDefinitions : Collection
var $parameterCases; $parameterCase; $parameterDefinition : Object
$parameterDefinitions:=$collector._parameterDefinitions()
$report.parameters:=New object("count"; $parameterDefinitions.length; "selectors"; $parameterDefinitions.extract("selector"); "cases"; New object)
$parameterCases:=New object(\
	"flagOne"; New object("ok"; True; "data"; New object("number"; 1; "text"; "")); \
	"flagZero"; New object("ok"; True; "data"; New object("number"; 0; "text"; "")); \
	"flagTwo"; New object("ok"; True; "data"; New object("number"; 2; "text"; "")); \
	"version"; New object("ok"; True; "data"; New object("number"; 0; "text"; "1.11.4")); \
	"versionEmpty"; New object("ok"; True; "data"; New object("number"; 0; "text"; "")); \
	"versionPath"; New object("ok"; True; "data"; New object("number"; 0; "text"; "/private/lib/libzip.dylib")); \
	"number"; New object("ok"; True; "data"; New object("number"; 1048576; "text"; "")); \
	"negative"; New object("ok"; True; "data"; New object("number"; -1; "text"; "")); \
	"fraction"; New object("ok"; True; "data"; New object("number"; 1.5; "text"; "")); \
	"overflow"; New object("ok"; True; "data"; New object("number"; 2147483648; "text"; "")); \
	"failed"; New object("ok"; False; "data"; New object("number"; 1; "text"; "1.0")); \
	"unimplemented"; New object("ok"; False; "unimplemented"; True; "data"; Null); \
	"remote"; New object("ok"; True; "remote"; True; "data"; Null); \
	"invalid"; New object("ok"; True; "data"; "private-parameter"))
// One definition per type: a flag, a version and each numeric unit.
For each ($name; OB Keys($parameterCases))
	$parameterCase:=New object
	For each ($parameterDefinition; $parameterDefinitions.query("id in :1"; New collection("db.hostWritable"; "db.libzipVersion"; "db.cacheUnloadMinimum"; "db.cacheFlushPeriodicity")))
		$parameterCase[$parameterDefinition.id]:=$collector._parameterMetric($parameterDefinition; $parameterCases[$name])
	End for each
	$report.parameters.cases[$name]:=$parameterCase
End for each
$report.parameters.live:=New object
For each ($measurement; $collector.parameters("static").combine($collector.parameters("settings")))
	$report.parameters.live[$measurement.id]:=New object("type"; $measurement.type; "unit"; $measurement.unit; "kind"; $measurement.kind; "availability"; $measurement.availability; "valueType"; Value type($measurement.value))
End for each
$report.parameters.staticInInfo:=($collector.staticMetrics.query("id = :1"; "db.libzipVersion").length=1)
$report.parameters.settingsInSnapshot:=($collector.snapshot().metrics.query("id = :1"; "db.cacheFlushPeriodicity").length=1)
HOST_Phase:="operator action normalization"
var $operator : cs.Dashboard._DashboardOperator
var $operatorFolder; $brokenFolder; $rotationFolder : 4D.Folder
var $operatorCases; $operatorMessage; $operatorValid; $operatorBegun; $operatorFrame; $operatorLine : Object
var $operatorLines : Collection
var $operatorText; $operatorRaw : Text
var $operatorBlob : Blob
$report.operator:=New object("validate"; New object; "violations"; New object)
$operator:=cs.Dashboard._DashboardOperator.new()
$operatorCases:=New object(\
	"null"; Null; \
	"text"; "operator.noop"; \
	"extraKey"; New object("actions"; New collection("operator.noop"); "audit"; "/private/audit"); \
	"empty"; New object("actions"; New collection); \
	"unknown"; New object("actions"; New collection("operator.shell")); \
	"duplicate"; New object("actions"; New collection("operator.noop"; "operator.noop")); \
	"nonText"; New object("actions"; New collection(1)); \
	"caseVariant"; New object("actions"; New collection("Operator.Noop")); \
	"valid"; New object("actions"; New collection("operator.noop")))
For each ($name; OB Keys($operatorCases))
	$report.operator.validate[$name]:=$operator.validate($operatorCases[$name])
End for each
$operatorFolder:=Folder(Temporary folder; fk platform path).folder("dashboard-operator-"+Generate UUID)
$operator:=cs.Dashboard._DashboardOperator.new(New collection("operator.noop"); "operator-epoch"; $operatorFolder)
$operatorValid:=New object("protocol"; 1; "kind"; "action"; "epoch"; "operator-epoch"; "id"; Generate digest("operator one"; SHA256 digest); "action"; "operator.noop"; "args"; New object("note"; "private sentinel"); "actor"; "0123456789abcdef")
$operatorBegun:=$operator.begin(OB Copy($operatorValid))
$report.operator.begin:=New object("ok"; $operatorBegun.ok; "frame"; $operatorBegun.frame; "idLength"; Length($operatorValid.id))
$report.operator.complete:=$operator.complete($operatorValid; $operatorBegun.record)
$operatorText:=$operatorFolder.file("audit.jsonl").getText()
$operatorLines:=Split string($operatorText; Char(10); sk ignore empty strings)
$report.operator.audit:=New object("lines"; $operatorLines.length; "states"; New collection; "keys"; Null; "private"; False)
For each ($operatorRaw; $operatorLines)
	$operatorLine:=JSON Parse($operatorRaw)
	$report.operator.audit.states.push($operatorLine.state)
	$report.operator.audit.keys:=OB Keys($operatorLine)
	$report.operator.audit.idDigest:=($operatorLine.id=Substring(Generate digest($operatorValid.id; SHA256 digest); 1; 16))
	$report.operator.audit.argsDigest:=($operatorLine.args=Substring(Generate digest("{\"note\":\"private sentinel\"}"; SHA256 digest); 1; 16))
	$report.operator.audit.actor:=$operatorLine.actor
	$report.operator.audit.utc:=Match regex("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\\.\\d{3}Z$"; $operatorLine.at)
End for each
$report.operator.audit.private:=(Position("private sentinel"; $operatorText; *)>0) | (Position($operatorValid.id; $operatorText; *)>0)
$operatorCases:=New object(\
	"wrongEpoch"; New object("epoch"; "other-epoch"); \
	"extraField"; New object("path"; "/private/path"); \
	"badId"; New object("id"; "short"); \
	"upperId"; New object("id"; Uppercase(Generate digest("operator two"; SHA256 digest))); \
	"badActor"; New object("actor"; "0123456789ABCDEF"); \
	"disabled"; New object("action"; "operator.shell"); \
	"extraArg"; New object("args"; New object("note"; "x"; "path"; "/private/path")); \
	"unsafeNote"; New object("args"; New object("note"; "a;rm")); \
	"longNote"; New object("args"; New object("note"; "123456789012345678901234567890123")); \
	"nonTextNote"; New object("args"; New object("note"; 1)); \
	"nonObjectArgs"; New object("args"; "private"); \
	"duplicate"; New object)
For each ($name; OB Keys($operatorCases))
	$operatorMessage:=OB Copy($operatorValid)
	If ($name#"duplicate")
		$operatorMessage.id:=Generate digest("operator "+$name; SHA256 digest)
	End if
	For each ($parameter; OB Keys($operatorCases[$name]))
		$operatorMessage[$parameter]:=$operatorCases[$name][$parameter]
	End for each
	$operatorBegun:=$operator.begin($operatorMessage)
	$report.operator.violations[$name]:=New object("ok"; $operatorBegun.ok; "error"; $operatorBegun.error)
End for each
$operatorMessage:=OB Copy($operatorValid)
OB REMOVE($operatorMessage; "actor")
$operatorMessage.id:=Generate digest("operator missing"; SHA256 digest)
$operatorBegun:=$operator.begin($operatorMessage)
$report.operator.violations.missingField:=New object("ok"; $operatorBegun.ok; "error"; $operatorBegun.error)
// Fail closed: an unwritable audit file means nothing runs.
$brokenFolder:=Folder(Temporary folder; fk platform path).folder("dashboard-operator-"+Generate UUID)
$brokenFolder.folder("audit.jsonl").create()
$operator.folder:=$brokenFolder
$operatorMessage:=OB Copy($operatorValid)
$operatorMessage.id:=Generate digest("operator broken"; SHA256 digest)
$operatorBegun:=$operator.begin($operatorMessage)
$report.operator.auditUnavailable:=New object("ok"; $operatorBegun.ok; "frame"; $operatorBegun.frame)
$operator.folder:=$operatorFolder
$operatorMessage.id:=Generate digest("operator incomplete"; SHA256 digest)
$operatorBegun:=$operator.begin($operatorMessage)
$operator.folder:=$brokenFolder
$report.operator.auditIncomplete:=New object("begin"; $operatorBegun.frame.state; "complete"; $operator.complete($operatorMessage; $operatorBegun.record))
// Rotation at 1 MiB keeps four files.
$rotationFolder:=Folder(Temporary folder; fk platform path).folder("dashboard-operator-"+Generate UUID)
$rotationFolder.create()
SET BLOB SIZE($operatorBlob; 1048576; 120)
$rotationFolder.file("audit.jsonl").setContent($operatorBlob)
$rotationFolder.file("audit.1.jsonl").setText("one")
$rotationFolder.file("audit.2.jsonl").setText("two")
$rotationFolder.file("audit.3.jsonl").setText("three")
$operator.folder:=$rotationFolder
$operatorMessage.id:=Generate digest("operator rotation"; SHA256 digest)
$operatorBegun:=$operator.begin($operatorMessage)
$operator.complete($operatorMessage; $operatorBegun.record)
$report.operator.rotation:=New object("first"; $rotationFolder.file("audit.1.jsonl").size; "second"; $rotationFolder.file("audit.2.jsonl").getText(); "third"; $rotationFolder.file("audit.3.jsonl").getText(); "fourth"; $rotationFolder.file("audit.4.jsonl").exists; "current"; Split string($rotationFolder.file("audit.jsonl").getText(); Char(10); sk ignore empty strings).length)
$report.operator.folder:=New object("matchesHost"; ($operator.defaultFolder().platformPath=Folder(fk logs folder).folder("dashboard").platformPath); "notComponent"; (Position("dashboard.4dbase"; $operator.defaultFolder().platformPath)=0))
$report.operator.monitorValidate:=$operator.validate(New object("actions"; New collection("monitor.diagnostics"; "operator.noop"; "monitor.cadence")))
$operator:=cs.Dashboard._DashboardOperator.new(New collection("monitor.cadence"; "monitor.diagnostics"; "operator.noop"); "operator-epoch"; Folder(Temporary folder; fk platform path).folder("dashboard-operator-"+Generate UUID))
$report.operator.monitor:=New object
$operatorCases:=New object(\
	"cadence2"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 2)); \
	"cadence5"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 5)); \
	"cadence10"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 10)); \
	"cadence1"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 1)); \
	"cadence3"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 3)); \
	"cadenceFraction"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 5.5)); \
	"cadenceText"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; "5")); \
	"cadenceExtra"; New object("action"; "monitor.cadence"; "args"; New object("seconds"; 5; "force"; True)); \
	"cadenceMissing"; New object("action"; "monitor.cadence"; "args"; New object); \
	"diagnostics"; New object("action"; "monitor.diagnostics"; "args"; New object); \
	"diagnosticsArgs"; New object("action"; "monitor.diagnostics"; "args"; New object("verbose"; True)))
For each ($name; OB Keys($operatorCases))
	$operatorMessage:=OB Copy($operatorValid)
	$operatorMessage.id:=Generate digest("monitor "+$name; SHA256 digest)
	$operatorMessage.action:=$operatorCases[$name].action
	$operatorMessage.args:=$operatorCases[$name].args
	$operatorBegun:=$operator.begin($operatorMessage)
	$report.operator.monitor[$name]:=New object("ok"; $operatorBegun.ok; "error"; $operatorBegun.error)
	If ($operatorBegun.ok)
		$report.operator.monitor[$name].state:=$operator.complete($operatorMessage; $operatorBegun.record).state
		$report.operator.monitor[$name].argsDigest:=$operatorBegun.record.args
	End if
End for each
$report.operator.monitor.expectedDigests:=New object("cadence5"; Substring(Generate digest("{\"seconds\":5}"; SHA256 digest); 1; 16); "diagnostics"; Substring(Generate digest("{}"; SHA256 digest); 1; 16))
$operator.folder.delete(Delete with contents)
HOST_Phase:="admin foundation units"
var $adminOperator : cs.Dashboard._DashboardOperator
var $adminFolder : 4D.Folder
var $adminMessage; $adminBegun; $adminCatalog : Object
var $adminCase : Text
var $adminAuthorizers : Object
$adminCatalog:=$operator.catalog()
$report.admin:=New object("catalogIds"; OB Keys($adminCatalog).orderBy(); "validate"; New object; "execute"; New object)
$report.admin.validate.authorizeNotFormula:=$operator.validate(New object("actions"; New collection("operator.noop"); "authorize"; "yes"))
$report.admin.validate.withAuthorize:=$operator.validate(New object("actions"; New collection("operator.noop"); "authorize"; Formula(True))).ok
$report.admin.validate.unknownKey:=$operator.validate(New object("actions"; New collection("operator.noop"); "policy"; "allow"))
$adminCatalog["test.tierB"]:=New object("id"; "test.tierB"; "tier"; "B"; "approval"; "operator+host"; "transport"; "tls_or_loopback_only"; "args"; New object)
$report.admin.validate.tierBWithout:=$operator.validate(New object("actions"; New collection("test.tierB")); $adminCatalog)
$report.admin.validate.tierBWith:=$operator.validate(New object("actions"; New collection("test.tierB"); "authorize"; Formula(True)); $adminCatalog).ok
$adminFolder:=Folder(Temporary folder; fk platform path).folder("dashboard-admin-"+Generate UUID)
$adminOperator:=cs.Dashboard._DashboardOperator.new(New collection("operator.exclusiveSleep"; "operator.noop"; "operator.sleep"); "admin-epoch"; $adminFolder)
$adminOperator.relay:=False
For each ($adminCase; New collection("operator.sleep"; "operator.exclusiveSleep"))
	$adminOperator.progressLog:=New collection
	$adminMessage:=New object("protocol"; 1; "kind"; "action"; "epoch"; "admin-epoch"; "id"; Generate digest("admin "+$adminCase; SHA256 digest); "action"; $adminCase; "args"; New object("seconds"; 2); "actor"; "0123456789abcdef")
	$adminBegun:=$adminOperator.begin($adminMessage)
	$report.admin.execute[$adminCase]:=New object("begin"; $adminBegun.frame; "canonical"; $adminBegun.canonical; \
		"final"; $adminOperator.execute($adminMessage; $adminBegun.record; $adminBegun.entry; $adminBegun.canonical; Null); "progress"; $adminOperator.progressLog)
End for each
$adminAuthorizers:=New object("deny"; Formula(False); "nonBoolean"; Formula("yes"); "throws"; Formula(JSON Parse("not json")); "allow"; Formula(True))
For each ($adminCase; OB Keys($adminAuthorizers))
	$adminMessage:=New object("protocol"; 1; "kind"; "action"; "epoch"; "admin-epoch"; "id"; Generate digest("authorize "+$adminCase; SHA256 digest); "action"; "operator.noop"; "args"; New object("note"; "x"); "actor"; "0123456789abcdef")
	$adminBegun:=$adminOperator.begin($adminMessage)
	$report.admin.execute["authorize_"+$adminCase]:=$adminOperator.execute($adminMessage; $adminBegun.record; $adminBegun.entry; $adminBegun.canonical; $adminAuthorizers[$adminCase])
End for each
$report.admin.auditStates:=New collection
For each ($operatorRaw; Split string($adminFolder.file("audit.jsonl").getText(); Char(10); sk ignore empty strings))
	$operatorLine:=JSON Parse($operatorRaw)
	$report.admin.auditStates.push($operatorLine.action+":"+$operatorLine.state+":"+String($operatorLine.error))
End for each
$adminFolder.delete(Delete with contents)
For each ($operatorFolder; New collection($operatorFolder; $brokenFolder; $rotationFolder))
	$operatorFolder.delete(Delete with contents)
End for each
HOST_Phase:="license usage normalization"
$licenseEntries:=New collection(\
	New object("productId"; 7; "productName"; "Client"; "productUsedCount"; 500; "productBalance"; 200; "token"; 123456; "reason"; "private caller"; "session"; New object("userName"; "private user")); \
	New object("productId"; 17; "productName"; "REST"; "globalProductUsedCount"; 999); \
	New object("productId"; 7; "productName"; "Client"; "productUsedCount"; 501))
$licenseCases:=New object(\
	"populated"; New object("ok"; True; "data"; $licenseEntries); \
	"empty"; New object("ok"; True; "data"; New collection); \
	"failed"; New object("ok"; False); \
	"null"; New object("ok"; True; "data"; Null); \
	"invalid"; New object("ok"; True; "data"; New collection(New object("productId"; "7"))))
$licenseEntries:=New collection
For ($productIndex; 1; 64)
	$licenseEntries.push(New object("productId"; $productIndex; "productName"; "Product"))
End for
$licenseCases.boundary:=New object("ok"; True; "data"; $licenseEntries.copy())
$licenseEntries.push(New object("productId"; 65; "productName"; "Product"))
$licenseCases.overflow:=New object("ok"; True; "data"; $licenseEntries)
$report.licenseUsage:=New object
// Execute in this order: known products must survive empty/error enumerations.
For each ($licenseCaseName; New collection("populated"; "empty"; "failed"; "null"; "invalid"; "overflow"; "boundary"))
	$licenseCase:=New object
	$normalized:=$collector._licenseUsageMetrics($licenseCases[$licenseCaseName])
	For each ($measurement; $normalized)
		$licenseCase[$measurement.id]:=$measurement
	End for each
	$report.licenseUsage[$licenseCaseName]:=$licenseCase
End for each
HOST_Phase:="async web service"
var $service : Object
var $event; $callbackLog; $duplicate; $oldService : Object
var $deadline : Integer
$callbackLog:=New shared object("events"; New shared collection; "action"; "")
$event:=New object("log"; $callbackLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$service:=$tool.start(New object; $event)
$report.sameFacadeRejected:=($tool.start(New object).status="failed")
$duplicate:=cs.Dashboard.Dashboard.new($target).start(New object)
$deadline:=Milliseconds+15000
While ((($service.samples<1) | ($callbackLog.events.length<3)) & ($service.status#"failed") & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.service:=New object("status"; $service.status; "samples"; $service.samples; "error"; $service.error)
$report.service.callbackError:=$service.callbackError
$report.service.callbackCount:=$callbackLog.events.length
$report.service.owned:=cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($service.port)
$report.service.duplicateRejected:=($duplicate.status="failed")
If (($service.status#"running") | ($service.samples<1))
	$report.success:=False
End if
HOST_Phase:="delayed retired controller finalization"
var $lifecycle : 4D.Signal
var $beforeFinalizer : Real
$beforeFinalizer:=$service.samples
$lifecycle:=New signal
CALL WORKER(".workers"; "Dashboard_lifecycle"; "retired"; $target; $service; $lifecycle)
If (Not($lifecycle.wait(5)))
	$report.success:=False
End if
$deadline:=Milliseconds+5000
While (($service.samples<=$beforeFinalizer) & Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.delayedFinalizer:=New object("oldFinished"; $lifecycle.oldFinished; "replacementOwned"; $lifecycle.replacementOwned; "replacementRunning"; ($service.status="running"); "replacementSampled"; ($service.samples>$beforeFinalizer))
If ($service.status="running")
	var $http : 4D.HTTPRequest
	var $origin : Text
	$origin:=Substring($service.url; 1; Position("/#token="; $service.url; *)-1)
	$http:=4D.HTTPRequest.new($origin+"/"; New object("timeout"; 3; "dataType"; "text"))
	$http.wait(4)
	$report.service.httpStatus:=$http.response.status
	If ($http.response.status#200)
		$report.success:=False
	End if
	$http:=4D.HTTPRequest.new($origin+"/api/events"; New object("timeout"; 3; "dataType"; "text"))
	$http.wait(4)
	$report.service.unauthenticatedStatus:=$http.response.status
	If ($http.response.status#401)
		$report.success:=False
	End if
End if
$tool.stop()
$deadline:=Milliseconds+5000
var $callbackStopped : Boolean
$callbackStopped:=False
While ((Not($service.finished) | Not($callbackStopped)) & (Milliseconds<$deadline))
	If ($callbackLog.events.length>0)
		$callbackStopped:=($callbackLog.events[$callbackLog.events.length-1].kind="stopped")
	End if
	DELAY PROCESS(Current process; 6)
End while
$report.callbackStopped:=$callbackStopped
$report.service.stopped:=($service.status="stopped")
$report.service.clearedURL:=($service.url="")
$report.service.pruned:=Not(cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($service.port))
$report.callbackSequence:=New collection
If ($callbackLog.events.length>=3)
	$report.callbackSequence:=New collection($callbackLog.events[0].kind; $callbackLog.events[1].kind; $callbackLog.events[2].kind)
End if
$report.callbackEvents:=$callbackLog.events.copy()
If (Not($report.service.stopped))
	$report.success:=False
End if
HOST_Phase:="terminate from a fresh facade"
var $orphan : Object
var $terminated; $idleTerminated : Boolean
$orphan:=cs.Dashboard.Dashboard.new($target).start(New object)
$deadline:=Milliseconds+15000
While (($orphan.status#"running") & Not($orphan.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$terminated:=cs.Dashboard.Dashboard.new().terminate()
$idleTerminated:=cs.Dashboard.Dashboard.new().terminate()
$report.terminate:=New object("wasRunning"; ($orphan.port>0); "returned"; $terminated; "finished"; $orphan.finished; "stopped"; ($orphan.status="stopped"); "clearedURL"; ($orphan.url=""); "pruned"; Not(cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($orphan.port)); "idle"; $idleTerminated)
If (Not($terminated) | Not($orphan.finished) | Not($idleTerminated) | ($orphan.port=0) | Not($report.terminate.pruned))
	$report.success:=False
End if
HOST_Phase:="CLI failure diagnostics"
$callbackLog:=New shared object("events"; New shared collection; "action"; "error-terminal")
$event:=New object("log"; $callbackLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$service:=$tool.start(New object("listen"; "localhost:0"); $event)
$deadline:=Milliseconds+5000
While ((Not($service.finished) | ($service.callbackError="")) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.serviceFailure:=New object("status"; $service.status; "clearedURL"; ($service.url=""); "diagnostic"; (Position("listen requires a concrete literal IP"; $service.error; *)>0); "callbackError"; ($service.callbackError#""))
If (($service.status#"failed") | Not($report.serviceFailure.diagnostic))
	$report.success:=False
End if
$tool.stop()
HOST_Phase:="stop before ready"
$service:=$tool.start(New object)
$tool.stop()
$deadline:=Milliseconds+7000
While (Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.cancelled:=New object("status"; $service.status; "finished"; $service.finished; "clearedURL"; ($service.url=""))
HOST_Phase:="callback exception"
$callbackLog:=New shared object("events"; New shared collection; "action"; "error")
$event:=New object("log"; $callbackLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$service:=$tool.start(New object; $event)
$deadline:=Milliseconds+10000
While (Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.callbackFailure:=New object("status"; $service.status; "finished"; $service.finished; "diagnostic"; ($service.callbackError#""); "clearedURL"; ($service.url=""))
HOST_Phase:="callback stop and restart"
$callbackLog:=New shared object("events"; New shared collection; "action"; "restart")
$event:=New object("log"; $callbackLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$service:=$tool.start(New object; $event)
$oldService:=$service
$tool.stop()
$deadline:=Milliseconds+15000
While (($callbackLog.events.length<5) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
// The original facade still owns its old generation; it must not stop the restart.
$tool.stop()
$report.staleHandle:=New object("oldFinished"; $oldService.finished)
$deadline:=Milliseconds+10000
While ((($callbackLog.events.length<5) | ($callbackLog.events[$callbackLog.events.length-1].kind#"stopped")) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.reentrantEvents:=$callbackLog.events.copy()
$report.staleHandle.restarted:=False
var $entry : Object
For each ($entry; $callbackLog.events)
	If (($entry.epoch#$oldService.epoch) & ($entry.kind="sample"))
		$report.staleHandle.restarted:=True
	End if
End for each
$report.staleHandle.pruned:=Not(cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($callbackLog.events[$callbackLog.events.length-1].port))
HOST_Phase:="occupied explicit port"
var $blocker : 4D.SystemWorker
var $resolved; $ready : Object
var $blockerState; $blockerOptions : Object
var $listen : Text
$resolved:=cs.Dashboard._CLI.new("dashboard"; $target).resolve()
$blockerState:=New shared object("url"; "")
$blockerOptions:=New object("dataType"; "text"; "encoding"; "UTF-8"; "hideWindow"; True; "timeout"; 10; "currentDirectory"; $resolved.file.parent; "buffer"; ""; "state"; $blockerState; "onData"; Formula(Dashboard_blocker($1; $2)))
$blocker:=4D.SystemWorker.new(cs.Dashboard._Process.new().quote($resolved.file.path)+" serve"; $blockerOptions)
$deadline:=Milliseconds+5000
While (($blockerState.url="") & (Milliseconds<$deadline))
	$blocker.wait(0.1)
End while
$ready:=New object("url"; $blockerState.url)
$listen:=Substring($ready.url; 8; Position("/#token="; $ready.url; *)-8)
$service:=$tool.start(New object("listen"; $listen))
$deadline:=Milliseconds+6000
While (Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.occupiedPort:=New object("status"; $service.status; "finished"; $service.finished; "diagnostic"; (Position("address already in use"; $service.error; *)>0); "clearedURL"; ($service.url=""))
$blocker.closeInput()
$blocker.wait(3)
If (Not($blocker.terminated))
	$blocker.terminate()
	$blocker.wait(1)
End if
$report.occupiedPort.blockerStopped:=$blocker.terminated
HOST_Phase:="IPv6 loopback and unexpected exit"
$callbackLog:=New shared object("events"; New shared collection; "action"; "")
$event:=New object("log"; $callbackLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$service:=$tool.start(New object("listen"; "[::1]:0"); $event)
$deadline:=Milliseconds+10000
While (($service.samples<1) & Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.ipv6:=New object("running"; ($service.status="running"); "url"; (Position("http://[::1]:"; $service.url; *)=1); "owned"; cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($service.port))
cs.workers.worker.new(cs.Dashboard._DashboardServer).terminate($service.port)
$deadline:=Milliseconds+5000
While (Not($service.finished) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.ipv6.unexpectedExit:=($service.status="failed")
$report.ipv6.pruned:=Not(cs.workers.worker.new(cs.Dashboard._DashboardServer).isRunning($service.port))
$deadline:=Milliseconds+3000
While ((Process number("Dashboard.callbacks."+$service.epoch)#0) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.callbackWorkerPruned:=(Process number("Dashboard.callbacks."+$service.epoch)=0)
HOST_Phase:="pending force termination"
var $forcedAgent : cs.Dashboard._DashboardAgent
var $forcedWorker : 4D.SystemWorker
var $forcedState : Object
$forcedState:=New shared object("status"; "starting"; "url"; ""; "error"; ""; "samples"; 0; "epoch"; Generate UUID; "port"; 0; "finished"; False; "stopRequested"; False; "forceDrain"; False)
$forcedAgent:=cs.Dashboard._DashboardAgent.new($target; New object; $forcedState; New object; $tool)
// Isolate the force primitive: this child is killed before readiness, never transferred or registered.
$forcedWorker:=4D.SystemWorker.new(cs.Dashboard._Process.new().quote($resolved.file.path)+" serve"; $forcedAgent)
$forcedAgent.worker:=$forcedWorker
$forcedAgent.force()
$forcedWorker.wait(2)
$report.forcedStop:=New object("terminated"; $forcedWorker.terminated; "finished"; $forcedState.finished; "status"; $forcedState.status)
HOST_Phase:="operator live action"
var $opTool : cs.Dashboard.Dashboard
var $opLog; $opEvent; $opService; $opHeaders; $opResponse; $opStatus; $opRecord : Object
var $opOrigin; $opViewer; $opToken; $opCookie; $opOperatorCookie; $opId; $opConfirmation; $opAudit; $opRequest; $opState; $opError : Text
var $opAuditFile : 4D.File
var $opLines : Collection
$opAuditFile:=Folder(fk logs folder).folder("dashboard").file("audit.jsonl")
If ($opAuditFile.exists)
	$opAuditFile.delete()
End if
$opLog:=New shared object("events"; New shared collection; "action"; "")
$opEvent:=New object("log"; $opLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$opTool:=cs.Dashboard.Dashboard.new($target)
$opService:=$opTool.start(New object("operator"; New object("actions"; New collection("operator.noop"))); $opEvent)
$deadline:=Milliseconds+15000
While (($opService.samples<1) & ($opService.status#"failed") & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.operatorLive:=New object("status"; $opService.status; "sampled"; ($opService.samples>0); "error"; $opService.error; \
	"urlShape"; Match regex("^http://127\\.0\\.0\\.1:[0-9]+/#token=[0-9a-f]{64}&operator=[0-9a-f]{64}$"; $opService.operatorUrl); \
	"viewerPrefix"; (Position($opService.url+"&operator="; $opService.operatorUrl; *)=1); "http"; New object)
If ($opService.status="running")
	$opOrigin:=Substring($opService.url; 1; Position("/#token="; $opService.url; *)-1)
	$opViewer:=Substring($opService.url; Position("/#token="; $opService.url; *)+8; 64)
	$opToken:=Substring($opService.operatorUrl; Position("&operator="; $opService.operatorUrl; *)+10; 64)
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/session"; New object("Origin"; $opOrigin); $opViewer)
	$opCookie:=String($opResponse.cookies.dashboard)
	$report.operatorLive.http.viewerSession:=$opResponse.status
	$opHeaders:=New object("Origin"; $opOrigin; "Cookie"; "dashboard="+$opCookie; "X-Dashboard-Action"; "operator"; "Content-Type"; "application/json")
	$report.operatorLive.http.viewerOnly:=Operator_http("GET"; $opOrigin+"/api/operator/status"; New object("Cookie"; "dashboard="+$opCookie); "").status
	$report.operatorLive.http.viewerTokenAsOperator:=Operator_http("POST"; $opOrigin+"/api/operator/session"; $opHeaders; JSON Stringify(New object("token"; $opViewer))).status
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/operator/session"; $opHeaders; JSON Stringify(New object("token"; $opToken)))
	$report.operatorLive.http.operatorSession:=$opResponse.status
	$opOperatorCookie:=String($opResponse.cookies.dashboard_operator)
	$opHeaders.Cookie:="dashboard="+$opCookie+"; dashboard_operator="+$opOperatorCookie
	$opRequest:=JSON Stringify(New object("action"; "operator.noop"; "args"; New object("note"; "live sentinel")))
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/operator/request"; $opHeaders; $opRequest)
	$report.operatorLive.http.request:=$opResponse.status
	$opConfirmation:=String(JSON Parse($opResponse.body).confirmation)
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/operator/confirm"; $opHeaders; JSON Stringify(New object("confirmation"; $opConfirmation; "action"; "operator.noop"; "args"; New object("note"; "other note"))))
	$report.operatorLive.http.argumentMismatch:=New object("status"; $opResponse.status; "error"; JSON Parse($opResponse.body).error)
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/operator/request"; $opHeaders; $opRequest)
	$opId:=String(JSON Parse($opResponse.body).id)
	$opConfirmation:=String(JSON Parse($opResponse.body).confirmation)
	$opResponse:=Operator_http("POST"; $opOrigin+"/api/operator/confirm"; $opHeaders; JSON Stringify(New object("confirmation"; $opConfirmation; "action"; "operator.noop"; "args"; New object("note"; "live sentinel"))))
	$report.operatorLive.http.confirm:=$opResponse.status
	$deadline:=Milliseconds+10000
	Repeat
		DELAY PROCESS(Current process; 6)
		$opStatus:=Operator_json(Operator_http("GET"; $opOrigin+"/api/operator/status"; New object("Cookie"; $opHeaders.Cookie); ""))
		$opRecord:=Null
		If (Value type($opStatus.records)=Is collection)
			$opRecord:=$opStatus.records.query("id = :1"; $opId).first()
		End if
		$opState:=""
		$opError:=""
		If ($opRecord#Null)
			$opState:=String($opRecord.state)
			$opError:=String($opRecord.error)
		End if
	Until (($opState="completed") | ($opState="failed") | (Milliseconds>$deadline))
	$report.operatorLive.http.final:=New object("state"; $opState; "error"; $opError)
	$report.operatorLive.http.replay:=Operator_http("POST"; $opOrigin+"/api/operator/confirm"; $opHeaders; JSON Stringify(New object("confirmation"; $opConfirmation; "action"; "operator.noop"; "args"; New object("note"; "live sentinel")))).status
	$opAudit:=""
	If ($opAuditFile.exists)
		$opAudit:=$opAuditFile.getText()
	End if
	$opLines:=Split string($opAudit; Char(10); sk ignore empty strings)
	$report.operatorLive.audit:=New object("lines"; $opLines.length; "states"; New collection; "matchesAction"; True; \
		"private"; (Position("sentinel"; $opAudit; *)>0) | (Position($opToken; $opAudit; *)>0) | (Position($opViewer; $opAudit; *)>0) | (Position($opCookie; $opAudit; *)>0) | (Position($opOperatorCookie; $opAudit; *)>0) | (Position($opConfirmation; $opAudit; *)>0) | (Position($opId; $opAudit; *)>0))
	For each ($operatorRaw; $opLines)
		$operatorLine:=JSON Parse($operatorRaw)
		$report.operatorLive.audit.states.push($operatorLine.state)
		$report.operatorLive.audit.matchesAction:=$report.operatorLive.audit.matchesAction & ($operatorLine.id=Substring(Generate digest($opId; SHA256 digest); 1; 16)) & ($operatorLine.epoch=$opService.epoch)
	End for each
	$report.operatorLive.http.logout:=Operator_http("POST"; $opOrigin+"/api/operator/logout"; $opHeaders; "{}").status
	$report.operatorLive.http.afterLogout:=Operator_http("GET"; $opOrigin+"/api/operator/status"; New object("Cookie"; $opHeaders.Cookie); "").status
End if
$opTool.stop()
$deadline:=Milliseconds+15000
While ((Not($opService.finished)) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.operatorLive.stopped:=New object("finished"; $opService.finished; "urlCleared"; ($opService.url=""); "operatorUrlCleared"; ($opService.operatorUrl=""))
HOST_Phase:="operator monitor controls"
var $mcTool : cs.Dashboard.Dashboard
var $mcLog; $mcEvent; $mcService; $mcHeaders; $mcResponse; $mcStatus; $mcRecord; $mcResult : Object
var $mcOrigin; $mcViewer; $mcToken; $mcCookie; $mcId; $mcDiagId; $mcConfirmation; $mcState; $mcAudit; $mcResultText : Text
var $mcBefore; $mcAfter; $mcLines; $mcAuditStates : Collection
var $mcValue : Variant
$mcLog:=New shared object("events"; New shared collection; "action"; "")
$mcEvent:=New object("log"; $mcLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$mcTool:=cs.Dashboard.Dashboard.new($target)
$mcService:=$mcTool.start(New object("operator"; New object("actions"; New collection("operator.noop"; "monitor.cadence"; "monitor.diagnostics"))); $mcEvent)
$deadline:=Milliseconds+15000
While (($mcService.samples<1) & ($mcService.status#"failed") & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.monitorLive:=New object("status"; $mcService.status; "error"; $mcService.error; "http"; New object)
If ($mcService.status="running")
	$mcOrigin:=Substring($mcService.url; 1; Position("/#token="; $mcService.url; *)-1)
	$mcViewer:=Substring($mcService.url; Position("/#token="; $mcService.url; *)+8; 64)
	$mcToken:=Substring($mcService.operatorUrl; Position("&operator="; $mcService.operatorUrl; *)+10; 64)
	$mcCookie:=String(Operator_http("POST"; $mcOrigin+"/api/session"; New object("Origin"; $mcOrigin); $mcViewer).cookies.dashboard)
	$mcHeaders:=New object("Origin"; $mcOrigin; "Cookie"; "dashboard="+$mcCookie; "X-Dashboard-Action"; "operator"; "Content-Type"; "application/json")
	$mcResponse:=Operator_http("POST"; $mcOrigin+"/api/operator/session"; $mcHeaders; JSON Stringify(New object("token"; $mcToken)))
	$mcHeaders.Cookie:="dashboard="+$mcCookie+"; dashboard_operator="+String($mcResponse.cookies.dashboard_operator)
	// Real owner-side timing at the default cadence.
	$mcBefore:=Operator_intervals($mcService; 3; 20000)
	$mcResponse:=Operator_http("POST"; $mcOrigin+"/api/operator/request"; $mcHeaders; JSON Stringify(New object("action"; "monitor.cadence"; "args"; New object("seconds"; 5))))
	$mcId:=String(JSON Parse($mcResponse.body).id)
	$mcConfirmation:=String(JSON Parse($mcResponse.body).confirmation)
	$report.monitorLive.http.cadenceRequest:=$mcResponse.status
	$report.monitorLive.http.cadenceConfirm:=Operator_http("POST"; $mcOrigin+"/api/operator/confirm"; $mcHeaders; JSON Stringify(New object("confirmation"; $mcConfirmation; "action"; "monitor.cadence"; "args"; New object("seconds"; 5)))).status
	$deadline:=Milliseconds+10000
	Repeat
		DELAY PROCESS(Current process; 3)
		$mcStatus:=Operator_json(Operator_http("GET"; $mcOrigin+"/api/operator/status"; New object("Cookie"; $mcHeaders.Cookie); ""))
		$mcRecord:=Null
		If (Value type($mcStatus.records)=Is collection)
			$mcRecord:=$mcStatus.records.query("id = :1"; $mcId).first()
		End if
		$mcState:=""
		If ($mcRecord#Null)
			$mcState:=String($mcRecord.state)
		End if
	Until (($mcState="completed") | ($mcState="failed") | (Milliseconds>$deadline))
	$report.monitorLive.cadence:=New object("state"; $mcState; "statusSeconds"; $mcStatus.cadence.seconds; "resultSeconds"; Null)
	If ($mcRecord#Null)
		If ($mcRecord.result#Null)
			$report.monitorLive.cadence.resultSeconds:=$mcRecord.result.seconds
		End if
	End if
	// Real owner-side timing after the approved change.
	$mcAfter:=Operator_intervals($mcService; 3; 30000)
	$report.monitorLive.timing:=New object("beforeCount"; $mcBefore.length; "afterCount"; $mcAfter.length; "beforeOk"; True; "afterOk"; True)
	For each ($mcValue; $mcBefore)
		$report.monitorLive.timing.beforeOk:=$report.monitorLive.timing.beforeOk & ($mcValue>=1500) & ($mcValue<=2700)
	End for each
	For each ($mcValue; $mcAfter)
		$report.monitorLive.timing.afterOk:=$report.monitorLive.timing.afterOk & ($mcValue>=4400) & ($mcValue<=5700)
	End for each
	If (Not($report.monitorLive.timing.beforeOk & $report.monitorLive.timing.afterOk))
		$report.monitorLive.timing.observed:=New object("before"; $mcBefore; "after"; $mcAfter)
	End if
	$mcResponse:=Operator_http("POST"; $mcOrigin+"/api/operator/request"; $mcHeaders; JSON Stringify(New object("action"; "monitor.diagnostics"; "args"; New object)))
	$mcDiagId:=String(JSON Parse($mcResponse.body).id)
	$mcConfirmation:=String(JSON Parse($mcResponse.body).confirmation)
	$report.monitorLive.http.diagnosticsConfirm:=Operator_http("POST"; $mcOrigin+"/api/operator/confirm"; $mcHeaders; JSON Stringify(New object("confirmation"; $mcConfirmation; "action"; "monitor.diagnostics"; "args"; New object))).status
	$deadline:=Milliseconds+10000
	Repeat
		DELAY PROCESS(Current process; 3)
		$mcStatus:=Operator_json(Operator_http("GET"; $mcOrigin+"/api/operator/status"; New object("Cookie"; $mcHeaders.Cookie); ""))
		$mcRecord:=Null
		If (Value type($mcStatus.records)=Is collection)
			$mcRecord:=$mcStatus.records.query("id = :1"; $mcDiagId).first()
		End if
		$mcState:=""
		If ($mcRecord#Null)
			$mcState:=String($mcRecord.state)
		End if
	Until (($mcState="completed") | ($mcState="failed") | (Milliseconds>$deadline))
	$report.monitorLive.diagnostics:=New object("state"; $mcState; "fields"; 0; "cadenceSeconds"; Null; "observedOk"; False; "private"; False)
	If ($mcRecord#Null)
		If (Value type($mcRecord.result)=Is object)
			$mcResult:=$mcRecord.result
			$mcResultText:=JSON Stringify($mcResult)
			$report.monitorLive.diagnostics.fields:=OB Keys($mcResult).length
			$report.monitorLive.diagnostics.cadenceSeconds:=$mcResult.cadence.seconds
			$report.monitorLive.diagnostics.observedOk:=($mcResult.cadence.observedIntervalsMs.length>=2)
			For each ($mcValue; $mcResult.cadence.observedIntervalsMs)
				$report.monitorLive.diagnostics.observedOk:=$report.monitorLive.diagnostics.observedOk & ($mcValue>=4400) & ($mcValue<=5700)
			End for each
			$report.monitorLive.diagnostics.private:=(Position($mcToken; $mcResultText; *)>0) | (Position($mcViewer; $mcResultText; *)>0) | (Position($mcCookie; $mcResultText; *)>0) | (Position($mcService.epoch; $mcResultText; *)>0) | (Position($mcOrigin; $mcResultText; *)>0) | (Position($mcId; $mcResultText; *)>0)
		End if
	End if
	$mcAudit:=""
	If ($opAuditFile.exists)
		$mcAudit:=$opAuditFile.getText()
	End if
	$mcAuditStates:=New collection
	For each ($operatorRaw; Split string($mcAudit; Char(10); sk ignore empty strings))
		$operatorLine:=JSON Parse($operatorRaw)
		If ($operatorLine.epoch=$mcService.epoch)
			$mcAuditStates.push($operatorLine.action+":"+$operatorLine.state+":"+$operatorLine.args)
		End if
	End for each
	$report.monitorLive.audit:=$mcAuditStates
	// M5: the shared in-memory history, read back over HTTP from the real CLI.
	var $hsFrom; $hsTo; $hsQuery : Text
	var $hsRaw; $hsMinute : Object
	var $hsBucket : Object
	var $hsBucketTotal : Integer
	// Time + Number is a Number in 4D: convert back to Time and roll the date across midnight.
	var $hsDate : Date
	var $hsSeconds : Integer
	$hsDate:=Current date
	$hsSeconds:=Current time+60
	If ($hsSeconds>=86400)
		$hsDate:=$hsDate+1
		$hsSeconds:=$hsSeconds-86400
	End if
	$hsTo:=String($hsDate; ISO date GMT; Time($hsSeconds))
	$hsDate:=Current date
	$hsSeconds:=Current time-1800
	If ($hsSeconds<0)
		$hsDate:=$hsDate-1
		$hsSeconds:=$hsSeconds+86400
	End if
	$hsFrom:=String($hsDate; ISO date GMT; Time($hsSeconds))
	$hsQuery:="metric=process.count&from="+$hsFrom+"&to="+$hsTo
	$report.monitorLive.history:=New object("unauthenticated"; Operator_http("GET"; $mcOrigin+"/api/history?"+$hsQuery+"&resolution=raw"; New object; "").status; \
		"badResolution"; Operator_http("GET"; $mcOrigin+"/api/history?"+$hsQuery+"&resolution=hour"; New object("Cookie"; "dashboard="+$mcCookie); "").status)
	$hsMinute:=Operator_http("GET"; $mcOrigin+"/api/history?"+$hsQuery+"&resolution=minute"; New object("Cookie"; "dashboard="+$mcCookie); "")
	$hsRaw:=Operator_http("GET"; $mcOrigin+"/api/history?"+$hsQuery+"&resolution=raw"; New object("Cookie"; "dashboard="+$mcCookie); "")
	$report.monitorLive.history.raw:=$hsRaw.status
	$report.monitorLive.history.minute:=$hsMinute.status
	If (($hsRaw.status=200) & ($hsMinute.status=200))
		$hsQuery:=$hsRaw.body
		$hsRaw:=JSON Parse($hsRaw.body)
		$hsMinute:=JSON Parse($hsMinute.body)
		$hsBucketTotal:=0
		For each ($hsBucket; $hsMinute.points)
			$hsBucketTotal+=$hsBucket.count+$hsBucket.gaps
		End for each
		$report.monitorLive.history.kind:=$hsRaw.metric.kind
		$report.monitorLive.history.coverage:=(Value type($hsRaw.coverage.rawSince)=Is text) & (Value type($hsMinute.coverage.minuteSince)=Is text)
		$report.monitorLive.history.rawCoversSamples:=($hsRaw.points.length>=$mcService.samples)
		$report.monitorLive.history.bucketsMatchRaw:=(Abs($hsBucketTotal-$hsRaw.points.length)<=1)
		$report.monitorLive.history.private:=(Position($mcToken; $hsQuery; *)>0) | (Position($mcService.epoch; JSON Stringify($hsRaw); *)>0)
	End if
End if
$mcTool.stop()
$deadline:=Milliseconds+15000
While ((Not($mcService.finished)) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.monitorLive.stopped:=New object("finished"; $mcService.finished; "operatorUrlCleared"; ($mcService.operatorUrl=""))
HOST_Phase:="abandoned sample skip"
// A request the agent stopped waiting for must not collect late and delay the next sample.
var $skipSampler : cs.Dashboard._DashboardSampler
var $skipSignal : 4D.Signal
$skipSampler:=cs.Dashboard._DashboardSampler.new(New shared object; New object; New object)
$skipSignal:=New signal
Use ($skipSignal)
	$skipSignal.abandoned:=True
End use
$skipSampler.sample($skipSignal)
$report.abandonedSample:=New object("skipped"; (Value type($skipSignal.payload)=Is undefined); "triggered"; $skipSignal.signaled)
$skipSignal:=New signal
$skipSampler.sample($skipSignal)
$report.abandonedSample.collectedWhenAwaited:=(Value type($skipSignal.payload)=Is text) & $skipSignal.signaled
HOST_Phase:="admin foundations live"
var $afTool : cs.Dashboard.Dashboard
var $afLog; $afEvent; $afService; $afHeaders; $afWait; $afHistory : Object
var $afOrigin; $afViewer; $afToken; $afCookie; $afId; $afStatusCookie; $afAudit : Text
var $afSamples; $afPaused; $afResumed : Integer
var $afCall : Object
var $afSecrets : Text
Use (Storage)
	Storage.adminCalls:=New shared collection
End use
$afLog:=New shared object("events"; New shared collection; "action"; "")
$afEvent:=New object("log"; $afLog; "onStatus"; Formula(Dashboard_callback($1; $2)))
$afTool:=cs.Dashboard.Dashboard.new($target)
$afService:=$afTool.start(New object("operator"; New object("actions"; New collection("operator.sleep"; "operator.exclusiveSleep"; "monitor.diagnostics"); "authorize"; Formula(Admin_authorize($1)))); $afEvent)
$deadline:=Milliseconds+15000
While (($afService.samples<1) & ($afService.status#"failed") & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.adminLive:=New object("status"; $afService.status; "error"; $afService.error)
If ($afService.status="running")
	$afOrigin:=Substring($afService.url; 1; Position("/#token="; $afService.url; *)-1)
	$afViewer:=Substring($afService.url; Position("/#token="; $afService.url; *)+8; 64)
	$afToken:=Substring($afService.operatorUrl; Position("&operator="; $afService.operatorUrl; *)+10; 64)
	$afCookie:=String(Operator_http("POST"; $afOrigin+"/api/session"; New object("Origin"; $afOrigin); $afViewer).cookies.dashboard)
	$afHeaders:=New object("Origin"; $afOrigin; "Cookie"; "dashboard="+$afCookie; "X-Dashboard-Action"; "operator"; "Content-Type"; "application/json")
	$afHeaders.Cookie:="dashboard="+$afCookie+"; dashboard_operator="+String(Operator_http("POST"; $afOrigin+"/api/operator/session"; $afHeaders; JSON Stringify(New object("token"; $afToken))).cookies.dashboard_operator)
	$afStatusCookie:=$afHeaders.Cookie
	// Non-exclusive: the executor runs it while .workers keeps sampling.
	$afSamples:=$afService.samples
	$afId:=Operator_action($afOrigin; $afHeaders; "operator.sleep"; New object("seconds"; 4))
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("running"); 5000)
	DELAY PROCESS(Current process; 150)
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("running"; "completed"); 2000)
	$report.adminLive.sleep:=New object("progressPhase"; String(Operator_field($afWait; "record.progress.phase")))
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("completed"; "failed"); 10000)
	$report.adminLive.sleep.state:=String(Operator_field($afWait; "record.state"))
	$report.adminLive.sleep.unverified:=(Operator_field($afWait; "record.unverified")=True)
	$report.adminLive.sleep.sampledDuring:=($afService.samples>=($afSamples+1))
	// Exclusive: sampling pauses and viewers see maintenance, then it resumes.
	$afId:=Operator_action($afOrigin; $afHeaders; "operator.exclusiveSleep"; New object("seconds"; 4))
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("running"); 5000)
	DELAY PROCESS(Current process; 60)
	$afPaused:=$afService.samples
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("running"); 2000)
	$report.adminLive.exclusive:=New object("target"; String(Operator_field($afWait; "status.target")))
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("completed"; "failed"); 10000)
	$report.adminLive.exclusive.state:=String(Operator_field($afWait; "record.state"))
	$report.adminLive.exclusive.pausedSamples:=($afService.samples=$afPaused)
	$deadline:=Milliseconds+8000
	While (($afService.samples<=$afPaused) & (Milliseconds<$deadline))
		DELAY PROCESS(Current process; 6)
	End while
	$report.adminLive.exclusive.resumed:=($afService.samples>$afPaused)
	// Fresh window: the last 30 minutes to one minute ahead (Time + Number is a Number; roll the date).
	$hsDate:=Current date
	$hsSeconds:=Current time+60
	If ($hsSeconds>=86400)
		$hsDate:=$hsDate+1
		$hsSeconds:=$hsSeconds-86400
	End if
	$hsTo:=String($hsDate; ISO date GMT; Time($hsSeconds))
	$hsDate:=Current date
	$hsSeconds:=Current time-1800
	If ($hsSeconds<0)
		$hsDate:=$hsDate-1
		$hsSeconds:=$hsSeconds+86400
	End if
	$hsFrom:=String($hsDate; ISO date GMT; Time($hsSeconds))
	$afHistory:=Operator_json(Operator_http("GET"; $afOrigin+"/api/history?metric=process.count&resolution=minute&from="+$hsFrom+"&to="+$hsTo; New object("Cookie"; "dashboard="+$afCookie); ""))
	$report.adminLive.exclusive.bands:=0
	$report.adminLive.exclusive.bandClosed:=False
	Case of
		: (Value type($afHistory.maintenance)#Is collection)
			$report.adminLive.exclusive.historyStatus:=$afHistory.httpStatus
		: ($afHistory.maintenance.length>0)
			$report.adminLive.exclusive.bands:=$afHistory.maintenance.length
			$report.adminLive.exclusive.bandClosed:=(Value type($afHistory.maintenance[0].to)=Is text) & (OB Keys($afHistory.maintenance[0]).length=2)
	End case
	// A blocked collector is answered collector_busy instead of ending the monitor.
	CALL WORKER("Dashboard.callbacks."+$afService.epoch; Formula(DELAY PROCESS(Current process; 480)))
	DELAY PROCESS(Current process; 720)
	$afSamples:=$afService.samples
	$deadline:=Milliseconds+8000
	While (($afService.samples<=$afSamples) & (Milliseconds<$deadline))
		DELAY PROCESS(Current process; 6)
	End while
	$report.adminLive.busy:=New object("status"; $afService.status; "sampledAfter"; ($afService.samples>$afSamples))
	$afId:=Operator_action($afOrigin; $afHeaders; "monitor.diagnostics"; New object)
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("completed"; "failed"); 10000)
	$report.adminLive.busy.collectorBusy:=(Num(Operator_field($afWait; "record.result.collectorBusy"))>=1)
	$report.adminLive.busy.pauses:=Num(Operator_field($afWait; "record.result.maintenancePauses"))
	// Orphan: the dashboard stops while an action runs; its result is audited, never sent to a newer instance.
	$afId:=Operator_action($afOrigin; $afHeaders; "operator.sleep"; New object("seconds"; 5))
	$afWait:=Operator_wait($afOrigin; $afStatusCookie; $afId; New collection("running"); 5000)
End if
$afTool.stop()
$deadline:=Milliseconds+15000
While ((Not($afService.finished)) & (Milliseconds<$deadline))
	DELAY PROCESS(Current process; 6)
End while
$report.adminLive.stopped:=New object("finished"; $afService.finished; "operatorUrlCleared"; ($afService.operatorUrl=""))
$deadline:=Milliseconds+10000
$afAudit:=""
Repeat
	DELAY PROCESS(Current process; 30)
	If ($opAuditFile.exists)
		$afAudit:=$opAuditFile.getText()
	End if
Until ((Position("\"state\":\"orphaned\""; $afAudit; *)>0) | (Milliseconds>$deadline))
$report.adminLive.audit:=New collection
For each ($operatorRaw; Split string($afAudit; Char(10); sk ignore empty strings))
	$operatorLine:=JSON Parse($operatorRaw)
	If ($operatorLine.epoch=$afService.epoch)
		$report.adminLive.audit.push($operatorLine.action+":"+$operatorLine.state+":"+String($operatorLine.error))
	End if
End for each
$report.adminLive.authorize:=New object("calls"; Storage.adminCalls.length; "actions"; Storage.adminCalls.extract("action"); "keys"; Null; "private"; False)
If (Storage.adminCalls.length>0)
	$report.adminLive.authorize.keys:=OB Keys(Storage.adminCalls[0]).orderBy()
	$afSecrets:=JSON Stringify(Storage.adminCalls)
	$report.adminLive.authorize.private:=(Position($afToken; $afSecrets; *)>0) | (Position($afViewer; $afSecrets; *)>0) | (Position($afCookie; $afSecrets; *)>0)
End if
HOST_Phase:="running failure watchdog"
$lifecycle:=New signal
CALL WORKER(".workers"; "Dashboard_lifecycle"; "failure"; $target; New object; $lifecycle)
If (Not($lifecycle.wait(8)))
	$report.success:=False
End if
$report.failureWatchdog:=New object("running"; $lifecycle.running; "watchdog"; $lifecycle.watchdog; "terminated"; $lifecycle.terminated; "finished"; $lifecycle.finished; "diagnostic"; $lifecycle.diagnostic; "pruned"; $lifecycle.pruned)
$report.finished:=True
ON ERR CALL(HOST_PreviousHandler; ek local)
$statusFile.setText(JSON Stringify($report))
HOST_StatusFile:=Null
HOST_Phase:=""
HOST_PreviousHandler:=""
QUIT 4D
