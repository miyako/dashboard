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
	If ($result.value.version#"0.1.4")
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
