# Dashboard capability inventory and implementation order

Research date: 2026-11-14 JST. Target: `miyako/dashboard`, **4D 21 LTS** minimum.
This is an operational-family inventory, not every information-producing
expression in the language and not a promise that every overload is supported.
Business methods, private application records and generic execution are excluded.
No administration is implemented by this inventory.

## Evidence and status

The read-only reference catalog HEAD was
`8a9945b0f91f368b6e6e0be0f1ad49f3ea1bdc10`: **21 R5 BETA**, build
`21R5.100156`, with 1,460 classic commands, 528 OOP members and 51 classes
(including namespaces/pseudo-classes). The 579 OOP top-level records are
51 classes plus 528 members, not 579 members. The snapshot names upstream docs
commit `78952faa7ceba81909b6b757a76108afa76f8993` and syntax resource SHA256
`ee27d9689e834bd1990d60d289d8c4e86e39beb723fe88c55b719e9d1e8bc411`.
These are recorded research provenance, not freshly recomputed source hashes
or 21 LTS runtime evidence.

The [complete per-API research catalog](dashboard-capability-catalog.md)
is preserved verbatim, including source/location/unit/thread/privacy/risk/cadence
profiles, uncertainty, provenance and exclusions. This document is its concise
overview and current implementation roadmap. The original inventory's SHA256 is
`018f59c49648fd132e177c79bd273df14d07bd4ec796c76243790e9dd21c263a`.
The catalog describes the research-time evidence and proposals, not current
runtime acceptance or a new public metric envelope. The implementation uses the
existing normalized metric contract described in README.
That research used official indexed excerpts and captured version-21 HTML;
it did not execute 4D. For this first increment, the official version-21
[DataStore.getInfo](https://developer.4d.com/docs/21/API/DataStoreClass#getinfo),
[DataClass.getInfo](https://developer.4d.com/docs/21/API/DataClassClass#getinfo),
[ds](https://developer.4d.com/docs/21/commands/ds),
[ORDA mapping](https://developer.4d.com/docs/21/ORDA/dsmapping) and
[component boundaries](https://developer.4d.com/docs/21/Extensions/develop-components)
were read directly. Actual acceptance must use the pinned **21.1 build 100562**,
not beta syntax checks.

**21** means the operation is documented in version 21; it does not verify
every selector, privilege, thread context or deployment. **Partial** means an
API exists but the stated contract must be completed before enabling it.
**Unknown** means insufficient version-21 evidence; **later** is excluded from
the LTS baseline. All unimplemented entries are candidates, not enabled features.
Specific privilege requirements remain unresolved unless stated below; that
never means unrestricted access. Dashboard authorization is a separate control.

**Local** means the collecting application/machine, not Server-wide information
when run on a client. **Engine** requires the eligible standalone/Server database;
**process** means current or explicitly identified process. Web metadata belongs
to the selected host/component web server, not this dashboard's Go HTTP service.
Owned-object status is only for integration-owned handles, never arbitrary probes.

## Observational information candidates

Each linked classic command uses the official `/docs/21/commands/` reference.
Grouped rows share their stated boundary; verify individual overloads before use.
Cadences are engineering proposals, not vendor guarantees or measured costs:
static once/manual refresh, small volatile scalars 5-15 seconds, bounded
enumerations 30-60 seconds, scans/history/diagnostics manual-only.

| Family / exact APIs and official reference | Evidence | Safe result, scope and unresolved boundary |
| --- | --- | --- |
| [Application info](https://developer.4d.com/docs/21/commands/application-info), Application type, Application version, Version type, Is compiled mode, Is macOS, Is Windows | 21; OS details partial | Local CPU percent, uptime seconds, network B/s, role/version/native bitfield; Windows warmup and OS CPU convention. Omit IPs, debugger IDs. Component/host compiled mode differs. |
| [System info](https://developer.4d.com/docs/21/commands/system-info) | 21 | Local core/thread/memory/OS metadata; verify each unit. No accounts, machine names, interfaces, volume/device paths. |
| [COMPONENT LIST](https://developer.4d.com/docs/21/commands/component-list), PLUGIN LIST | 21 | Bounded counts, not names/IDs. A component cannot privately install a host plug-in. |
| [Application file](https://developer.4d.com/docs/21/commands/application-file), Data file, Structure file, Get 4D file, Get 4D folder | 21 | Derive approved presence/size locally, never paths. Host/component and selector scope differ. No arbitrary filesystem scan. |
| [License info](https://developer.4d.com/docs/21/commands/license-info) | 21 | **Reloads rights from disk**, so cached/manual, not a pure polling getter. Null outside local licensing; omit keys, numbers, identity/company/email. |
| [License usage](https://developer.4d.com/docs/21/commands/license-usage), Is license available | 21 | Server retained-record counts, not current capacity; retention-time balances must not be summed. Availability is not free-client census; plugin assignments matter. |
| [Last errors](https://developer.4d.com/docs/21/commands/last-errors), Call chain, Last query plan, Last query path | errors 21; chain unknown; query diagnostics partial | Errors only inside handler/Try context; process-specific, redacted codes only. No stacks, code names, query literals/record keys. |
| [Cache info](https://developer.4d.com/docs/21/commands/cache-info), Get cache size, MEMORY STATISTICS, Database measures | 21 | Engine memory bytes and selected cumulative I/O bytes/counts; selector units differ. Remote client unsupported/empty is not zero. No native detailed objects/history initially. History has 200-sample cap and unavailable `-1`. |
| [Get adjusted blobs cache priority](https://developer.4d.com/docs/21/commands/get-adjusted-blobs-cache-priority), Get adjusted index cache priority, Get adjusted table cache priority | 21 | Effective priorities; exact field/table/thread scope unresolved. |
| [Process activity](https://developer.4d.com/docs/21/commands/process-activity), Process info, Process state, Process number, Current process, Current process name, Process aborted, Count tasks, Count user processes, Count users | 21; user count scope partial | Local visible activity vs internal tasks; Server session enumeration distinct. Process CPU fraction 0..1, CPU time seconds. Count inclusion/thread scope needs verification; no names/stale identity control. |
| [Session](https://developer.4d.com/docs/21/commands/session), Session info, Session storage | 21 | Current/server-session context, not arbitrary private storage. Session info docs' Integer input vs returned Text UUID remains unresolved; no guessed overload. |
| [Locked records info](https://developer.4d.com/docs/21/commands/locked-records-info), Is record locked, Is data file locked, In transaction, Transaction level, Semaphore | 21/partial per context | Aggregate lock state only; write-protected file is not record locking. Process transactions are not global inventory. Semaphore testing can acquire ownership: not a pure getter. No records loaded just to probe. |
| [GET TABLE TITLES](https://developer.4d.com/docs/21/commands/get-table-titles), GET FIELD TITLES, Last table number, Last field number, Table, Field, Table name, Field name, GET TABLE PROPERTIES, GET FIELD PROPERTIES, GET FIELD ENTRY PROPERTIES, GET RELATION PROPERTIES, GET MISSING TABLE NAMES, Is table number valid, Is field number valid | 21/partial | Bounded table/field/indexed/relation counts; upper table/field numbers are not counts. Physical vs virtual/ORDA mapping differs. Names/IDs remain private. Field indexed flags are not a complete index inventory. |
| [GET AUTOMATIC RELATIONS](https://developer.4d.com/docs/21/commands/get-automatic-relations), GET FIELD RELATION, TRIGGER PROPERTIES, Records in table, Table fragmentation, Get external data path | automatic relations unknown; others 21/partial | Process relation/trigger context is not global integrity. Record counts require consistency review; logical-record fragmentation percent is a potentially costly manual check, not index/disk fragmentation. External-storage paths private. |
| [GET DOCUMENT PROPERTIES](https://developer.4d.com/docs/21/commands/get-document-properties), Get document size, VOLUME LIST, VOLUME ATTRIBUTES, EXPORT STRUCTURE, Export structure file | 21/partial; document size unknown | Fixed metadata only; verify volume units. Structure export can be large/private and file export writes disk; unnecessary for first increment. No structure XML returned. |
| [BACKUP INFO](https://developer.4d.com/docs/21/commands/backup-info), RESTORE INFO | 21/partial | Last/next/status/duration; cooperative where documented, duration milliseconds, date/time normalization required. Omit archive/data paths. No trigger merely to create metrics. |
| [Log file](https://developer.4d.com/docs/21/commands/log-file), Last update log path, CHECK LOG FILE | 21/partial | Journal/update-log presence/approved sizes only; consistency check manual, exact result/UI/side effects unresolved. Logs and journal record contents excluded. |
| [Get database parameter](https://developer.4d.com/docs/21/commands/get-database-parameter), Get database localization | 21; selector contracts partial | Closed read-selector allowlist, separate read/write units, persistence and application/component scope. No arbitrary selector IDs. |
| [WEB Get server info](https://developer.4d.com/docs/21/commands/web-get-server-info), WEB Is server running, WEB GET STATISTICS, WEB GET OPTION, WEB Server, WEB Server list, WEB Is secured connection, SOAP Get info | 21/partial | Effective runtime differs from configured options. `withCache:false`; large web-cache descriptions forbidden. Current-request TLS is not global posture. Host/component selection and Server deployment required. |
| [HTTP GET OPTION](https://developer.4d.com/docs/21/commands/http-get-option), HTTP Get certificates folder | partial | Outbound client context, not inbound web health; fixed configuration presence only, no paths. |
| [SQL GET OPTION](https://developer.4d.com/docs/21/commands/sql-get-option), SQL GET LAST ERROR, SQL Get current data source, SQL GET DATA SOURCE LIST | 21; selector units partial | Current SQL context; error codes/local driver counts only. DSNs, driver error text and credentials private; configured port does not prove running service. |
| [GET /rest/$info](https://developer.4d.com/docs/21/REST/info) | 21; supplemental REST API | Aggregate cache/entity-set counts only after access-policy verification; no IDs, users, labels or progress/privilege objects. |
| [Data file encryption status](https://developer.4d.com/docs/21/commands/data-file-encryption-status) | 21 | Prefer eligible main datastore booleans; no key material or arbitrary file paths. |
| [Current user](https://developer.4d.com/docs/21/commands/current-user), Current system user, Current client authentication, Get default user | 21/partial | Identity excluded; SSO may contact domain controller (Windows-specific), not a harmless cross-platform scalar. Alias is not security identity. |
| [GET USER LIST](https://developer.4d.com/docs/21/commands/get-user-list), GET USER PROPERTIES, GET GROUP LIST, GET GROUP PROPERTIES, Get group access, User in group, Is user deleted, Get plugin access | 21/partial | Count/approved membership flags only; cooperative commands, access-privilege/password-system contention errors. Project group IDs ephemeral; binary-only properties differ. No invented universal Designer rule. |

### Configuration selector sub-inventory

Source: [Get database parameter](https://developer.4d.com/docs/21/commands/get-database-parameter)
and separately [SET DATABASE PARAMETER](https://developer.4d.com/docs/21/commands/set-database-parameter).
Some GET selectors are read-only. Verify selector-specific thread safety, scope,
range and persistence; never automatically round-trip GET values into SET.

| Selectors | Evidence and meaning |
| --- | --- |
| Is current database a project (112), Is host database a project (113), Is host database writable (117) | 21, read-only 0/1; structure writability is not data-file permission. |
| Libldap version (114), Libsasl version (115), Libzip version (120), OpenSSL version (94) | 21, local library version only. |
| Cache flush periodicity (95) | 21 GET and SET both document seconds, >1, standalone/Server, thread-safe, session override. No supposed unit mismatch. |
| Cache unload minimum size (66), 4D Server timeout (13) | Partial: unload unit needs verification; timeout SET minutes/sign persistence known, GET equivalence not established. |
| 4D Remote mode timeout (14), Idle connections timeout (54), Remote connection sleep timeout (98) | 21: first is legacy-network-only; others seconds, sign/connection scope differs, Server sleep check may lag 300 seconds. |
| 4D Server log recording (28), Client log recording (45), Debug log recording (34), Current process debug log recording (111), Diagnostic log recording (79), Diagnostic log level (86), Log command list (80), Circular log limitation (90), Pause logging (121), TCPUDP log recording (131) | Mostly partial; process/client/Server scope distinct. Log contents/code filters private. Debug standard timestamps milliseconds vs tabbed microseconds. Pausing logging can hide evidence. |
| SQL Server Port ID (88), Client Server port ID (35), Server base process stack size (53) | 21/partial; configured ports not live service; stack bytes, no tuning initially. |
| Min TLS version (105), SSL cipher list (64), Use legacy network layer (87) | Partial except cipher text-out shape (numeric return 0 is not disabled TLS); verify enum/runtime transport. |
| Table sequence number (31), Times inside objects (109) | 21: sequence not row count; setter changes future IDs. Object time conversion does not override ORDA/SQL seconds. |

### OOP metadata and owned objects

| Exact members / official version-21 class | Evidence / boundary |
| --- | --- |
| [DataStore](https://developer.4d.com/docs/21/API/DataStoreClass): getInfo(), encryptionStatus(), locked(), getGlobalStamp(), getAllRemoteContexts(), getRemoteContextInfo(), getRequestLog(), isAdminProtected() | 21; type/networked safe; encryption/lock eligibility local/Server only. Stamps not activity rates. Context/log objects may contain names, attributes and request contents: aggregate only after bounded-contract review. The full [isAdminProtected() body](https://developer.4d.com/docs/21/API/DataStoreClass#isadminprotected) documents a Boolean since 18 R6: True if Data Explorer access is disabled for the working session. This is not dashboard authorization and has no new runtime proof here. |
| [DataClass](https://developer.4d.com/docs/21/API/DataClassClass): getInfo(), getCount(), getDataStore(), attributeName, getRemoteCache() | 21; `getInfo` exposes `{exposed,name,primaryKey,tableNumber}` internally. First PR counts only. `getCount` is record access, not needed for metadata. Attributes describe schema, not values; remote cache contains entities/keys, excluded. |
| [Entity](https://developer.4d.com/docs/21/API/EntityClass): getStamp(), isNew(), touched(), touchedAttributes() | Partial, existing-record context only; no arbitrary entity creation/loading for telemetry. |
| [Session](https://developer.4d.com/docs/21/API/SessionClass): info, id, userName, storage, expirationDate, idleTimeout, getPrivileges(), hasPrivilege(), isGuest() | 21; current-session context. Expiry date/time and idle minutes distinct. Privilege getters omit promoted process privileges; web/REST enforcement is not desktop authorization. IDs/identity/storage excluded. |
| [WebServer](https://developer.4d.com/docs/21/API/WebServerClass): isRunning, name, HTTPEnabled, HTTPPort, HTTPSEnabled, HTTPSPort, HTTPTrace, HTTPCompressionLevel, HTTPCompressionThreshold, HSTSEnabled, HSTSMaxAge, CORSEnabled, CORSSettings, minTLSVersion, cipherSuite, perfectForwardSecrecy, openSSLVersion, accessKeyDefined, certificateFolder, IPAddressToListen, rootFolder, defaultHomepage, characterSet, debugLog, logRecording, maxRequestSize, maxConcurrentProcesses, maxSessions, keepSession, scalableSession, inactiveSessionTimeout, inactiveProcessTimeout, sessionCookieDomain, sessionCookieName, sessionCookiePath, sessionCookieSameSite, sessionIPAddressValidation, handlers, rules | 21/partial per property; getter/setter/startup/thread semantics must be completed. Counts/flags only for origins, routes, handlers; no names/keys/cookie IDs/IPs/paths. maxRequestSize bytes; legacy session limits/timeouts not scalable quotas. |
| [Document/File](https://developer.4d.com/docs/21/API/Document): exists, size, modificationDate, modificationTime, creationDate, creationTime, extension; [Directory/Folder](https://developer.4d.com/docs/21/API/Directory): exists, files(), folders(); [FileHandle](https://developer.4d.com/docs/21/API/FileHandleClass): getSize(), eof, offset, mode | Partial; owned fixed files only, nonrecursive bounded counts, bytes and separately normalized dates/times. No content, aliases, paths or arbitrary constructors. |
| [SystemWorker](https://developer.4d.com/docs/21/API/SystemWorkerClass): pid, exitCode, terminated, errors, timeout; [HTTPAgent](https://developer.4d.com/docs/21/API/HTTPAgentClass): requestsCount, freeSocketsCount; [HTTPRequest](https://developer.4d.com/docs/21/API/HTTPRequestClass): terminated, errors; [TCPListener](https://developer.4d.com/docs/21/API/TCPListenerClass): port, errors; [TCPConnection](https://developer.4d.com/docs/21/API/TCPConnectionClass): closed, port, errors | Partial; existing integration-owned objects, not OS/global socket inventory. No command lines, responses, payloads, addresses, credentials or new connectivity probes. |

**Later, not enabled:** `DataClass.getIndexes()` (21 R5),
`Session.quotas` / `Session.info.unreachableSince` (21 R4),
`WebServer.quotas` and quota-start settings (21 R5). The 51-class beta catalog
is not a supported LTS class list.
`GET INDEXES` was not a classic catalog command and is **not proposed**.
Use documented indexed field flags or separately scoped structure metadata;
neither is equivalent to `DataClass.getIndexes()` or index-build progress.

## Administrative candidates, never polling

These are classifications, **not authorization to implement or execute**.
Every mutation needs exact per-API contracts, operator authorization, target
binding, redacted audit, finite execution, postconditions and recovery.

| Exact APIs / official family reference | Risk / proposed disposition |
| --- | --- |
| [FLUSH CACHE](https://developer.4d.com/docs/21/commands/flush-cache), SET CACHE SIZE, SET/ADJUST BLOBS CACHE PRIORITY, SET/ADJUST INDEX CACHE PRIORITY, SET/ADJUST TABLE CACHE PRIORITY | 21, disruptive engine tuning/eviction; never routine dashboard maintenance. Synthetic CRUD flushes are test-only. |
| [PAUSE PROCESS](https://developer.4d.com/docs/21/commands/pause-process), RESUME PROCESS, ABORT PROCESS, SET PROCESS PRIORITY, SEND MESSAGE TO REMOTE USER | 21/partial; consequential control/notification. Never internal/system targets or stale/recycled identifiers. |
| [START TRANSACTION](https://developer.4d.com/docs/21/commands/start-transaction), VALIDATE TRANSACTION, CANCEL TRANSACTION, UNLOAD RECORD; Entity.lock()/unlock() | Process/record ownership changes, not global unlock/admin endpoints. Catalog-only absent explicit application requirements. |
| [DataStore](https://developer.4d.com/docs/21/API/DataStoreClass): flushAndLock(), unlock(), clearAllRemoteContexts(), setRemoteContextInfo(), startRequestLog(), stopRequestLog(), setGlobalStamp(), provideDataKey(), setAdminProtection(), startTransaction(), cancelTransaction(), validateTransaction(), makeSelectionsAlterable(); DataClass.clearRemoteCache()/setRemoteCacheSettings() | 21/partial: locks same-process/nested, backup/VSS/MSC owners not released. Logging writes sensitive contents. Admin protection distinct from operator roles. Cache clearing causes load; keys/transactions/global stamps excluded from general surface. |
| [BACKUP](https://developer.4d.com/docs/21/commands/backup), SET DATABASE PARAMETER, SET DATABASE LOCALIZATION, LOG EVENT, ACTIVITY SNAPSHOT | 21/partial; backup async completion/recovery; config persistence; snapshots/logging potentially sensitive disk writes. Bounded redacted owned audit may be useful later. |
| [WEB START SERVER](https://developer.4d.com/docs/21/commands/web-start-server), WEB STOP SERVER, WEB SET OPTION, WEB SET ROOT FOLDER, WEB SET HOME PAGE, WEB LEGACY CLOSE SESSION, SOAP REJECT NEW REQUESTS; WebServer.start()/stop() | 21/partial; legacy close/SOAP admission unknown. May remove own transport; require independent recovery. No automatic service restart. |
| [HTTP SET OPTION](https://developer.4d.com/docs/21/commands/http-set-option), HTTP SET CERTIFICATES FOLDER, SQL SET OPTION, START SQL SERVER, STOP SQL SERVER, SQL LOGIN, SQL LOGOUT | 21/partial, service/connection/trust or credential changes; not telemetry. Arbitrary SQL EXECUTE/SCRIPT/export explicitly excluded. |
| [Session](https://developer.4d.com/docs/21/API/SessionClass): setPrivileges(), clearPrivileges(), promote(), demote(), createOTP(), restore() | 21; security/identity mutations, not authentication-by-assignment or generic privilege escalation. OTP/storage/identity private. |
| [Set user properties](https://developer.4d.com/docs/21/commands/set-user-properties), Set group properties, DELETE USER, CHANGE CURRENT USER, CHANGE PASSWORD, SET USER ALIAS, SET GROUP ACCESS, SET PLUGIN ACCESS, USERS TO BLOB, BLOB TO USERS | 21/partial; explicit access errors, project/binary behavior differs. Component has unusable commands; no universal component admin wrapper. Credentials/import/destructive changes excluded. |
| [Refresh license](https://developer.4d.com/docs/21/commands/refresh-license), CHANGE LICENSES, Create deployment license | Partial; entitlement/network changes and licensing material, not telemetry. |
| [VERIFY CURRENT DATA FILE](https://developer.4d.com/docs/21/commands/verify-current-data-file), VERIFY DATA FILE | 21; potentially heavy scans/physical index checks, manual maintenance only, approved targets and bounded diagnostics. |
| [RESTORE](https://developer.4d.com/docs/21/commands/restore), INTEGRATE MIRROR LOG FILE, Compact data file, OPEN DATA FILE, CREATE DATA FILE, OPEN DATABASE, SET UPDATE FOLDER, Encrypt data file, Discover data key, Register data key, New data key, TRUNCATE TABLE | Destructive/offline/code-supply/key operations: catalog-only, no general dashboard endpoint. |
| [CREATE INDEX](https://developer.4d.com/docs/21/commands/create-index), DELETE INDEX, SET INDEX, PAUSE INDEXES, RESUME INDEXES, IMPORT STRUCTURE, REGENERATE MISSING TABLE, SET EXTERNAL DATA PATH, RELOAD EXTERNAL DATA | 21/partial; costly schema/recovery/index/storage changes, catalog-only. Beta vector-index overloads are not LTS evidence. |
| [New log file](https://developer.4d.com/docs/21/commands/new-log-file), SELECT LOG FILE, LOG FILE TO JSON | 21; journal rollover/recovery-chain changes or private record export, not ordinary diagnostics. |
| [RELOAD PROJECT](https://developer.4d.com/docs/21/commands/reload-project), RESTART 4D, QUIT 4D, TRACE | Disruptive; TRACE unknown headless contract. Separate opt-in, recovery access and actual Server/client tests required. |
| SystemWorker.terminate(), HTTPRequest.terminate(), TCPListener.terminate(), TCPConnection.shutdown() | Partial, owned objects only after lifecycle/recovery validation; never arbitrary PID/connection control. |

## Ordered small-PR roadmap

| Order | Implementation boundary | Acceptance before merging |
| --- | --- | --- |
| 1: merged | Static main-datastore type/networked and mapped/exposed/unexposed dataclass counts in existing metrics; cache once, cap 512, redact all identifiers. No new envelope, actions, queries or later APIs. | Focused null/error/malformed/privacy/512/513 tests; dataless host plus genuine synthetic data host; real 21.1 compile and exact unpacked compiled ZIP host calls. Native Server/client/Windows remain separate `not_run` boundaries. |
| 2a: this increment (host scope blocked) | Cooperative allowlisted `BACKUP INFO` normalization: host-local last/next times, uninterpreted status code, milliseconds duration and validated UTC begin timestamp. Deployed host metrics fail closed as unsupported until component-to-host targeting is established. Cache eligibility outcomes >=60 seconds; no rate graphs/actions. | Exact positive/absent/invalid/error/privacy/unit/midnight/zero-duration normalizer assertions; independent dataless and fresh direct-host/component no-backup source/compiled fixtures. Matching absent histories cannot prove target. Actual positive host targeting/scheduled backup and real Server/client/IDE remain `not_run`; no backup initiated to manufacture evidence. |
| 2b: next separate read-only PRs | Eligible encryption/admin-protection/lock flags; physical field/index counts; configured vs effective web metadata; allowlisted config/library versions; owned CLI health. | Complete partial contracts first, verify units/thread scope and denied states; size/time/single-flight budgets, no scans to create measurements. Real Server/client/web deployments for their respective fields. |
| 3 | Action safety substrate **before any action**: closed action IDs/parameters, real operator authentication and per-action default-deny authorization, host/target binding, expiring confirmation, request IDs/replay rules, bounded queue/time, redacted durable audit. | Unauthorized/wrong-host/stale-target/replay/cancel/race tests; accepted async request distinguished from completed postcondition; no automatic non-idempotent retry. No arbitrary SQL/method/formula/path/PID/token execution. |
| 4 | Separately approved bounded owned diagnostics/cancellation or fixed-template notification; manual only. ORDA cache clear only after exact client scope/load consequences established. | Owned-target and cleanup/postcondition/recovery tests; capped duration/output, no production FLUSH CACHE/free-all or automatic tuning. |
| 5 | Higher-risk opt-in PRs: backup trigger, admission/disconnect/abort, cache/config/security changes, SQL/web lifecycle, reload/restart/quit. | Real Server plus client fixtures, consequential confirmation and async postcondition; independent recovery transport, no internal targets. |
| 6 | Destructive/offline restore/replay/compaction/encryption/key/schema/index/import/truncate/data-file/user-import work remains catalog-only. | Separate authorized requirements and disposable backup/restore/recovery evidence, never inferred from read-only telemetry. |

Each coherent increment is implemented, verified, committed and reviewed/merged
before the next PR. This document does not authorize release/version changes.

## Validation and exclusions

`passed` means actual execution on the named revision/artifact/platform;
`failed` means executed failure; `not_run` is neither success nor waiver.
Required separate deployments include 21 LTS standalone, Server + remote client,
web/scalable sessions/REST, host/component web servers and Windows-only
counter/SSO/VSS behavior. Tool4d evidence is not IDE/Server/Dependency Manager
installation evidence; beta catalog controls prove only beta syntax.

Use sentinel native objects containing names, IPs, paths, keys, tokens,
persistent IDs, record/query contents and storage, and assert they cannot cross
CLI/HTTP/log/audit boundaries. Only allowlisted scalars and bounded aggregate
counts are permitted; never raw native-object serialization. Empty/Null/denied/
unsupported/invalid/overflow results must not invent zero or partial success.
Local client metrics remain local; configured ports/settings are not effective
service state; schema exposure is not access authorization.

Excluded: application `cs.*` business members; entity/selection queries and
CRUD/navigation/serialization; generic SQL/method/formula/path execution; private
logs/stacks/record keys/session storage; credentials/license keys/OTP/key rotation;
UI/windows/forms/menus/printing/Write Pro/View Pro; mail/LDAP/payload transports;
generic compiler/class-store/design introspection, collection/math/JSON/XML/BLOB/
resource manipulation; filesystem changes and recursive scans; arbitrary network
constructors/probes. None becomes an admin endpoint just because it is in the
1,460-command or 528-member catalog.
