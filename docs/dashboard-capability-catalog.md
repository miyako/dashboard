# 4D dashboard capability inventory

Research date: 2026-11-14 JST. Target: miyako/dashboard, minimum 4D 21 LTS.
Reference repository was read only. No 4D instance, database, administration command, Git reference, release setting, credential, or other repository was changed.

## Scope and provenance

This is a scope-defined candidate inventory, not a claim to enumerate every information-producing expression in the 4D language. It covers engine/application/host health, process and session activity, licenses, locks and transactions, schema/index/storage metadata, backup/journal/logging, network and SQL/web/REST services, security posture, user/group administration, cache and maintenance, and configuration. It excludes application business methods and private application records.

Actually inspected:

- `out/4d-command-ir.json`: 1,460 command records (counted command-level `displayName` fields).
- `out/manifest.json`: 1,460 classic entries (independently counted `displayName` fields).
- `out/4d-oop-ir.json`: 579 top-level record display names, comprising 51 classes and 528 members; do not report 579 members.
- `out/oop_manifest.json`: 528 member keys.
- `out/oop_classes.json`: 51 class records (independently counted). These include namespaces/pseudo-classes and later-release classes, not 51 guaranteed 21 LTS instance classes.
- `out/r5_snapshot.json`, `out/oop_refresh_review.json`, and compiler provenance. Snapshot declares 1,460 commands, 528 members and 51 classes, agreeing with the counts above.
- Actual checkout HEAD: `8a9945b0f91f368b6e6e0be0f1ad49f3ea1bdc10`, NOT the guide's `1dfd4e7eb832d19361f8ec1f4801603899087ca3`.
- Snapshot-declared upstream docs commit: `78952faa7ceba81909b6b757a76108afa76f8993`.
- Corpus/compiler: **21 R5 BETA**, build `21R5.100156`. Snapshot-declared syntax resource SHA-256: `ee27d9689e834bd1990d60d289d8c4e86e39beb723fe88c55b719e9d1e8bc411`.
- Snapshot records classic IR SHA-256 `ad0f59c2831aba100b103288f00cc54c15f579933096f6bac60221c43f2bb87c` and classic manifest SHA-256 `d5b74a34ce8f8bd78c005f5acfc1125aca9f0b8406cbcf90972da13f4960324f`. These are recorded provenance, not freshly recomputed checksums.

Search method: classic theme-based selection across 4D Environment, System Environment, Processes, Process (Communications), Cache Management, Backup, Structure Access, Transactions, Users and Groups, Licenses, Web Server, SQL, Data Security, Tools and Records returned 273 theme matches; supplementary searches covered Record Locking, Relations, Table, Interruptions, Secured Protocol, storage and diagnostics. This 273 is a search intermediate, not the final inventory size. OOP member-name inspection covered DataStore, DataClass, Entity, Session, WebServer, filesystem, owned workers and network objects. Follow-up source reading, not keyword matches alone, determined inclusion and release caveats.

Evidence tiers:

- **21**: command/member present in the official version-21 theme/page or captured version-21 HTML inspected here. Confirms documented availability of the specified operation, not every beta overload/property.
- **21-partial**: API exists in 21; contract details, selector-specific privileges, units or deployment behavior remain unresolved as stated. Not implementation-ready until those details are checked.
- **later**: explicit later-release history and absence of the corresponding member heading in the inspected 21 page.
- **unknown**: catalog candidate without enough version-21 contract evidence. Do not enable it merely because beta syntax accepts it.

Public official search results were accessible and corroborated key contracts at `https://developer.4d.com/docs/21/...`. Direct `web_fetch` and subsequent shell processing requests were denied because no interactive approval was available; no bypass was attempted. Captured official HTML under `mirror/docs/21/` supplied additional readable evidence. Search results are indexed excerpts with crawl dates, not a fresh full-page HTTP verification. Versionless URLs are used below ONLY for explicit later-release history, never to prove 21 LTS availability. No authenticated request to `4d/docs` was attempted.

## How to read the records

Every row supplies exact API name, official source, availability, result/units, execution profile and semantic/risk profile. Profiles are part of each record; row-specific restrictions override them.

Execution profiles:

- **HOST**: information about the machine/application executing the code: standalone desktop, client, or Server; client-local is NOT server-wide. Thread safety unspecified unless `TS` is shown. Server deployment required to validate Server fields.
- **ENGINE**: standalone 4D or Server-side host database; remote client must use an explicitly server-executed collector where supported. Thread safety unspecified unless `TS`. Real Server/client deployment required for networked correctness.
- **PROCESS**: calling/identified process; not a global transaction/query/error inventory. Desktop/client/Server applicability and exact thread safety need per-command verification when unspecified.
- **WEB**: the selected host/component web server or current web request/session; a client can run a separate web server. Test actual HTTP/REST/session configurations and Server deployment.
- **OWNED**: an existing object owned by the dashboard integration; not enumeration of all OS/network objects. No arbitrary process/connection/file creation to make a metric exist.
- **U**: precise execution/thread restrictions unresolved; do not execute/enable until official contract is completed.
- **TS**: inspected source says thread-safe. This does not make its entire calling chain or plugin safe.
- **COOP**: inspected source says not thread-safe; route through a cooperative process. Selector-specific exceptions must be explicit.

Semantics/cost/cadence profiles (engineering recommendations, NOT measured timings or vendor-guaranteed safe rates):

- **R1**: observational scalar/small object; low expected collection cost; propose 5-15 seconds for volatile metrics, startup/manual refresh for static metadata. No automatic collection until location and privacy rules are verified.
- **R2**: enumeration/detailed object; cost scales with processes, sessions, tables, contexts, files or cache objects; propose 30-60 seconds with hard output limits, aggregation and single-flight collection.
- **R3**: potentially expensive scan, detailed history, diagnostic or sensitive snapshot; manual only, bounded scope/timeout, maintenance window if appropriate.
- **A1**: bounded mutation, explicit operator action only; no polling/retry loop; authorization, audit, confirmation and postcondition required. Not automatically low risk because reversible.
- **A2**: service/session/process/security/configuration disruption or persistence; disabled by default, deployment test and recovery procedure required.
- **A3**: data-destructive/data-file/key/schema/offline operation; catalog only, no general dashboard execution path.
- **X**: useful to explain/exclude a family but not a proposed dashboard endpoint.

Privileges: unless a record says otherwise, **specific built-in privilege requirements were not established**. This is not a claim that no privilege is required. Dashboard authorization is a separate required application control. User/group inspection explicitly documents access-privilege errors and password-system contention; do not invent a universal Designer-only rule. Web/REST ORDA resource permissions and web administration access are distinct from desktop user/group memberships.

Sensitive fields: never serialize whole native result objects. Suppress account names/emails, license numbers/keys, tokens/OTP/session UUIDs and persistent IDs, machine names, IPs, filesystem paths, query literals/record keys, arbitrary logs/stacks and session storage. Return only allowlisted scalar metadata and bounded aggregate counts. Schema names themselves may be private; expose counts or explicitly approved labels only.

## Application, host, licensing and diagnostics

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Application info](https://developer.4d.com/docs/21/commands/application-info) | 21 | Object: CPU percent, uptime seconds, network throughput bytes/second, PID, headless/service and transport flags. Windows counters need prior initialization. Mac CPU interpretation is per documented core convention. Omit IP lists/debugger session ID. | HOST TS | R1 |
| [Application type](https://developer.4d.com/docs/21/commands/application-type) | 21 | Integer application-kind enum; retain native enum and normalized label. | HOST | R1 |
| [Application version](https://developer.4d.com/docs/21/commands/application-version) | 21 | Text version; optional build output/options. Do not parse beta version strings as LTS capability proof. | HOST | R1 |
| [Version type](https://developer.4d.com/docs/21/commands/version-type) | 21 | Integer product/runtime type enum, not OS architecture or license count. | HOST | R1 |
| [Is compiled mode](https://developer.4d.com/docs/21/commands/is-compiled-mode) | 21 | Boolean; optional component/host distinction must be preserved. | HOST | R1 |
| [Is macOS](https://developer.4d.com/docs/21/commands/is-macos) | 21-partial | Boolean executing host OS. | HOST | R1 |
| [Is Windows](https://developer.4d.com/docs/21/commands/is-windows) | 21-partial | Boolean executing host OS. | HOST | R1 |
| [System info](https://developer.4d.com/docs/21/commands/system-info) | 21 | Object: cores, CPU threads, model, Rosetta status, OS/hardware and volume metadata. Omit account/machine names, network interfaces/IPs, mount points/device identifiers. Verify each volume/memory unit before exposing it. | HOST TS | R2 |
| [COMPONENT LIST](https://developer.4d.com/docs/21/commands/component-list) | 21 | Names array; publish count only unless labels approved. | HOST | R2 |
| [PLUGIN LIST](https://developer.4d.com/docs/21/commands/plugin-list) | 21 | Parallel ID/name arrays; publish bounded count/approved plugin presence. | HOST | R2 |
| [Application file](https://developer.4d.com/docs/21/commands/application-file) | 21 | Executable path text; derive existence/extension locally, never expose raw path. | HOST | R1 |
| [Data file](https://developer.4d.com/docs/21/commands/data-file) | 21 | Data-segment path text; not a file-size metric. | ENGINE | R1 |
| [Structure file](https://developer.4d.com/docs/21/commands/structure-file) | 21 | Structure/project path text; component/host option matters. | HOST | R1 |
| [Get 4D file](https://developer.4d.com/docs/21/commands/get-4d-file) | 21 | Selector-derived path text; allowlist selector and derive scalar metadata only. | HOST | R1 |
| [Get 4D folder](https://developer.4d.com/docs/21/commands/get-4d-folder) | 21 | Selector-derived folder path text; component/host distinction. | HOST | R1 |
| [License info](https://developer.4d.com/docs/21/commands/license-info) | 21 | Object/Null where no locally used license, e.g. remote client. Product counts/expiry may be useful. Suppress key/licenseNumber/userName/userMail/companyName. **Reloads license files and updates rights if modified.** | HOST | A1, not a pure R1 getter; manual/cached |
| [License usage](https://developer.4d.com/docs/21/commands/license-usage) | 21 | Collection of retained-license objects: product ID/name, retained/remaining/global counts, time/reason and nested session. Retention-time counts are not necessarily a current aggregate. Suppress token and all session identifiers/identity fields. | Server only; Null elsewhere; thread U | R2; Server deployment mandatory |
| [Is license available](https://developer.4d.com/docs/21/commands/is-license-available) | 21 | Boolean plugin/license availability or demo-mode test, not free-client-license count. Accounts for assigned plugin access. | HOST COOP | R1 |
| [Refresh license](https://developer.4d.com/docs/21/commands/refresh-license) | 21-partial | License refresh result/behavior requires full contract; may contact/update licensing state. | U | A2 |
| [CHANGE LICENSES](https://developer.4d.com/docs/21/commands/change-licenses) | 21-partial | Changes license configuration; no credential-taking dashboard endpoint. | U | A2 |
| [Create deployment license](https://developer.4d.com/docs/21/commands/create-deployment-license) | 21-partial | Produces deployment licensing material; outside operational telemetry. | U | A3/X |
| [Last errors](https://developer.4d.com/docs/21/commands/last-errors) | 21 | Error stack collection, or Null if no error; **must be called in an ON ERR CALL handler or Try/Try-Catch context**. Capture redacted codes during error handling, not general polling. Includes thrown objects. | PROCESS/error context | R1 event-driven only |
| [Call chain](https://developer.4d.com/docs/21/commands/call-chain) | unknown | Call-stack metadata; not a global profiler; code names/paths may be sensitive. | PROCESS | R3 |
| [Last query plan](https://developer.4d.com/docs/21/commands/last-query-plan) | 21-partial | Query-plan text, process-scoped and dependent on query diagnostics; retain summarized operator counts only. | PROCESS | R3 |
| [Last query path](https://developer.4d.com/docs/21/commands/last-query-path) | 21-partial | Executed query-path text, not a query to run; no literals/records exported. | PROCESS | R3 |
| [ACTIVITY SNAPSHOT](https://developer.4d.com/docs/21/commands/activity-snapshot) | 21-partial | Produces diagnostic snapshot output; not a cheap observational scalar and may write sensitive diagnostic files. | U | R3/A1 |
| [LOG EVENT](https://developer.4d.com/docs/21/commands/log-event) | 21-partial | Writes a log event; potential target for bounded redacted audit, not an information command. | HOST, thread U | A1 |
| [TRACE](https://developer.4d.com/docs/21/commands/trace) | unknown | Enters/debugs execution; disruptive and UI-related. | PROCESS | A2/X |

## Cache and engine measures

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Cache info](https://developer.4d.com/docs/21/commands/cache-info) | 21 | Object `{maxMem,usedMem,objects}`; allowlist total memory scalars and verify units; detailed loaded objects can be large. `dbFilter:"All"` expands to running databases/components. | ENGINE TS; do not call in remote mode | R2 |
| [Get cache size](https://developer.4d.com/docs/21/commands/get-cache-size) | 21 | Real cache size in bytes (also corroborated by SET CACHE SIZE example). | ENGINE; not remote | R1 |
| [MEMORY STATISTICS](https://developer.4d.com/docs/21/commands/memory-statistics) | 21 | Parallel names/values/count arrays; values represent differing metric kinds, not universally bytes. Publish selected metric names with verified units only. | HOST/ENGINE TS; scope per infoType must be checked | R2 |
| [Database measures](https://developer.4d.com/docs/21/commands/database-measures) | 21 | Object rooted at `DB`; byte/count measures, table/index/segment details, histories. Internal history holds at most 200 relevant samples; `-1` is unavailable/too old, zero may mean no event. Prefer selected global scalar totals, no histories initially. | ENGINE TS; empty object on remote client; host DB in component | R1 for filtered totals; R3 for detailed histories |
| [Get adjusted blobs cache priority](https://developer.4d.com/docs/21/commands/get-adjusted-blobs-cache-priority) | 21 | Integer effective/adjusted priority for table blobs. | ENGINE; thread U | R1 |
| [Get adjusted index cache priority](https://developer.4d.com/docs/21/commands/get-adjusted-index-cache-priority) | 21 | Integer effective/adjusted field-index priority. | ENGINE; thread U | R1 |
| [Get adjusted table cache priority](https://developer.4d.com/docs/21/commands/get-adjusted-table-cache-priority) | 21 | Integer effective/adjusted table priority. | ENGINE; thread U | R1 |
| [FLUSH CACHE](https://developer.4d.com/docs/21/commands/flush-cache) | 21 | Writes dirty buffers to disk; optional bytes-to-free or `*` empties cache. Vendor says ordinarily unnecessary; freeing production cache is discouraged. | ENGINE TS | A2; not routine maintenance/polling |
| [SET CACHE SIZE](https://developer.4d.com/docs/21/commands/set-cache-size) | 21 | Changes cache bytes and optional minimum-free bytes dynamically. No automatic resizing. | ENGINE TS; not remote | A2 |
| [SET BLOBS CACHE PRIORITY](https://developer.4d.com/docs/21/commands/set-blobs-cache-priority) | 21 | Changes table-blob priority; bounds/persistence need per-command review. | ENGINE U | A2 |
| [SET INDEX CACHE PRIORITY](https://developer.4d.com/docs/21/commands/set-index-cache-priority) | 21 | Changes field-index priority. | ENGINE U | A2 |
| [SET TABLE CACHE PRIORITY](https://developer.4d.com/docs/21/commands/set-table-cache-priority) | 21 | Changes table priority. | ENGINE U | A2 |
| [ADJUST BLOBS CACHE PRIORITY](https://developer.4d.com/docs/21/commands/adjust-blobs-cache-priority) | 21 | Adjusts table-blob priority. | ENGINE U | A2 |
| [ADJUST INDEX CACHE PRIORITY](https://developer.4d.com/docs/21/commands/adjust-index-cache-priority) | 21 | Adjusts field-index priority. | ENGINE U | A2 |
| [ADJUST TABLE CACHE PRIORITY](https://developer.4d.com/docs/21/commands/adjust-table-cache-priority) | 21 | Adjusts table priority. | ENGINE U | A2 |

## Processes, sessions, locks and transactions

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Process activity](https://developer.4d.com/docs/21/commands/process-activity) | 21 | Object containing processes and, on Server, sessions. Includes internal processes not addressable by Process info. 21 adds web sessions. Server filters by sessionID/options; invalid ID -> Null. Clients/local always return local processes and ignore filters. Redact names/IDs/identity. | HOST; Server deployment essential | R2 |
| [Process info](https://developer.4d.com/docs/21/commands/process-info) | 21 | Object/Null for invalid process number: cpuTime seconds, **cpuUsage fraction 0..1**, creation timestamp, state/type, preemptive/visible; IDs differ from local number. | HOST/identified process; thread U | R1 |
| [Process state](https://developer.4d.com/docs/21/commands/process-state) | 21 | Integer state enum for identified process. | PROCESS | R1 |
| [Process number](https://developer.4d.com/docs/21/commands/process-number) | 21 | Integer lookup from name/ID; transient identifiers, not authorization. | PROCESS | R1 |
| [Current process](https://developer.4d.com/docs/21/commands/current-process) | 21 | Integer collector process number; not OS PID. | PROCESS | R1 |
| [Current process name](https://developer.4d.com/docs/21/commands/current-process-name) | 21 | Text; omit arbitrary method/process names. | PROCESS | R1 |
| [Process aborted](https://developer.4d.com/docs/21/commands/process-aborted) | 21 | Boolean about current process; not remote abort postcondition by itself. | PROCESS | R1 |
| [Count tasks](https://developer.4d.com/docs/21/commands/count-tasks) | 21 | Integer; native task count differs from filtered user-process count. | HOST; precise inclusion U | R1 |
| [Count user processes](https://developer.4d.com/docs/21/commands/count-user-processes) | 21 | Integer native user-process count. | HOST; precise inclusion U | R1 |
| [Count users](https://developer.4d.com/docs/21/commands/count-users) | 21 | Integer user count; not identical to license usage or all web sessions. | U; validate Server | R1 |
| [Session](https://developer.4d.com/docs/21/commands/session) | 21 | Current `4D.Session` object, not global session inventory. | PROCESS/WEB | R1 |
| [Session info](https://developer.4d.com/docs/21/commands/session-info) | 21 | Object/Null; 21 page declares **Integer input sessionId** while returned ID is Text UUID. Do not silently substitute UUID input. Desktop session metadata; current session can use `.info`. Redact names/IP/persistent IDs. | PROCESS/Server desktop sessions; thread U | R1; signature discrepancy needs LTS validation |
| [Session storage](https://developer.4d.com/docs/21/commands/session-storage) | 21 | Object with application-owned shared session data. No private contents inspected/exported. | Session ID-specific | X |
| [Locked records info](https://developer.4d.com/docs/21/commands/locked-records-info) | 21 | Per-table object; aggregate lock counts only, never record IDs or owner identity. Invalid object on remote client; server-executed method supported; component uses host DB. | ENGINE TS | R2; bounded table list |
| [Locked](https://developer.4d.com/docs/21/commands/locked) | 21 | Boolean for current record; False also if no current record. False does not mean universally unlocked: current process may own the writable record. Do NOT load records just to collect this metric. | PROCESS TS | X/R1 only for already owned context |
| [LOCKED BY](https://developer.4d.com/docs/21/commands/locked-by) | 21 | Out parameters process/user/session-user/process-name for current record; deleted record can produce process -1. No owner names exported. | PROCESS; thread U | X/R1 |
| [Read only state](https://developer.4d.com/docs/21/commands/read-only-state) | 21 | Boolean current-process table access mode, not data-file lock or global security policy. | PROCESS | R1 |
| [Is data file locked](https://developer.4d.com/docs/21/commands/is-data-file-locked) | 21 | Boolean: opened data file or at least one segment is **write-protected**. Distinct from record locks, encryption-key state and `ds.locked()` write freeze. | ENGINE; exact remote applicability U | R1 |
| [Active transaction](https://developer.4d.com/docs/21/commands/active-transaction) | 21 | True for current process transaction only if not suspended; False for absent OR suspended transaction. Pair with In transaction to distinguish these states. | PROCESS | R1 |
| [In transaction](https://developer.4d.com/docs/21/commands/in-transaction) | 21-partial | Boolean transaction context; not global count of active transactions. | PROCESS | R1 |
| [Transaction level](https://developer.4d.com/docs/21/commands/transaction-level) | 21-partial | Integer nesting depth for process. | PROCESS | R1 |
| [Test semaphore](https://developer.4d.com/docs/21/commands/test-semaphore) | 21-partial | Boolean existence of an explicitly named application semaphore; no global enumeration. | U | R1 only approved own semaphore |
| [Semaphore](https://developer.4d.com/docs/21/commands/semaphore) | 21-partial | Boolean, but creates/claims semaphore as part of test; NOT observational. | U | A1/X |
| [CLEAR SEMAPHORE](https://developer.4d.com/docs/21/commands/clear-semaphore) | 21-partial | Releases semaphore; can break application coordination. | U | A2 |
| [ABORT PROCESS BY ID](https://developer.4d.com/docs/21/commands/abort-process-by-id) | 21 | Stops Server process using unique process ID, not local process number. Full eligibility/asynchrony contract must be checked. | Server; thread U | A2; never arbitrary internal processes |
| [PAUSE PROCESS](https://developer.4d.com/docs/21/commands/pause-process) | 21 | Pauses identified process; blocking/interference risk. | PROCESS U | A2 |
| [RESUME PROCESS](https://developer.4d.com/docs/21/commands/resume-process) | 21 | Resumes process; not a universal safe unlock. | PROCESS U | A2 |
| [DELAY PROCESS](https://developer.4d.com/docs/21/commands/delay-process) | 21 | Delays process in ticks (1/60 second); not a scheduler for dashboard refresh. | PROCESS U | A2/X |
| [DROP REMOTE USER](https://developer.4d.com/docs/21/commands/drop-remote-user) | 21 | Asynchronous disconnect by session ID. Does nothing on client or standalone. May terminate work/transactions. | Server only | A2 |
| [SEND MESSAGE TO REMOTE USER](https://developer.4d.com/docs/21/commands/send-message-to-remote-user) | 21 | Operator message to remote user(s); user-visible and Server validation needed. Use fixed templates/length/rate/target bounds. | U; intended Server | A1 |
| [REJECT NEW REMOTE CONNECTIONS](https://developer.4d.com/docs/21/commands/reject-new-remote-connections) | 21 | Sets whether application server accepts new remote connections; no-op on client/standalone. Not web/REST access control. | Server only | A2 |
| [START TRANSACTION](https://developer.4d.com/docs/21/commands/start-transaction) | 21-partial | Starts process transaction. Not a dashboard control over another process. | PROCESS | A2/X |
| [VALIDATE TRANSACTION](https://developer.4d.com/docs/21/commands/validate-transaction) | 21-partial | Commits process transaction and data changes. | PROCESS | A3/X |
| [CANCEL TRANSACTION](https://developer.4d.com/docs/21/commands/cancel-transaction) | 21-partial | Cancels process transaction; data/work loss potential. | PROCESS | A3/X |
| [SUSPEND TRANSACTION](https://developer.4d.com/docs/21/commands/suspend-transaction) | 21-partial | Changes transaction state in process. | PROCESS | A2/X |
| [RESUME TRANSACTION](https://developer.4d.com/docs/21/commands/resume-transaction) | 21-partial | Changes transaction state in process. | PROCESS | A2/X |

Process execution facilities (`Execute on server`, `EXECUTE ON CLIENT`, `New process`, `CALL WORKER`, `CALL FORM`, client registration and process-variable access) are transport/implementation mechanisms, not operator-selectable admin actions. Never accept arbitrary method names, source/formulas or process-variable names from a Go CLI request.

## Tables, fields, indexes and storage

Availability for classic schema entries below is corroborated by the [official 21 Structure Access theme](https://developer.4d.com/docs/21/commands/theme/Structure-Access); it does not prove beta vector-index variants.

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Last table number](https://developer.4d.com/docs/21/commands/last-table-number) | 21 | Integer upper table-number bound, NOT count; holes require validity checks. | ENGINE | R1 |
| [Is table number valid](https://developer.4d.com/docs/21/commands/is-table-number-valid) | 21 | Boolean for numeric table ID. | ENGINE | R1 |
| [Table name](https://developer.4d.com/docs/21/commands/table-name) | 21 | Text; schema label can be private. | ENGINE | R1 |
| [Table](https://developer.4d.com/docs/21/commands/table) | 21 | Pointer/number conversion; internal helper only, no pointer serialization. | ENGINE | X |
| [Last field number](https://developer.4d.com/docs/21/commands/last-field-number) | 21 | Integer upper field-number bound, NOT field count. | ENGINE | R1 |
| [Is field number valid](https://developer.4d.com/docs/21/commands/is-field-number-valid) | 21 | Boolean field validity. | ENGINE | R1 |
| [Field name](https://developer.4d.com/docs/21/commands/field-name) | 21 | Text; publish approved label/count only. | ENGINE | R1 |
| [Field](https://developer.4d.com/docs/21/commands/field) | 21 | Pointer/number conversion; internal helper. | ENGINE | X |
| [GET TABLE PROPERTIES](https://developer.4d.com/docs/21/commands/get-table-properties) | 21 | Boolean output flags: invisible and trigger options. No arbitrary table reads needed. | ENGINE | R2 |
| [GET FIELD PROPERTIES](https://developer.4d.com/docs/21/commands/get-field-properties) | 21 | Output type, length, indexed/unique/invisible flags. Indexed flag is NOT complete index-definition/status inventory. | ENGINE | R2 |
| [GET FIELD ENTRY PROPERTIES](https://developer.4d.com/docs/21/commands/get-field-entry-properties) | 21 | List and entry-validation flags; schema-only optional metadata, no UI rollout needed. | ENGINE | R2/X |
| [GET RELATION PROPERTIES](https://developer.4d.com/docs/21/commands/get-relation-properties) | 21 | Related table/field and automatic relation flags. | ENGINE | R2 |
| [GET MISSING TABLE NAMES](https://developer.4d.com/docs/21/commands/get-missing-table-names) | 21 | Names array, aggregate missing-table count only. | ENGINE | R2 |
| [GET TABLE TITLES](https://developer.4d.com/docs/21/commands/get-table-titles) | 21-partial | Names/numbers arrays; virtual/display titles may differ from schema. | ENGINE | R2 |
| [GET FIELD TITLES](https://developer.4d.com/docs/21/commands/get-field-titles) | 21-partial | Field titles/numbers arrays; same privacy rule. | ENGINE | R2 |
| [GET AUTOMATIC RELATIONS](https://developer.4d.com/docs/21/commands/get-automatic-relations) | unknown | Process relation configuration output, not global relational integrity check. | PROCESS | R1/X |
| [GET FIELD RELATION](https://developer.4d.com/docs/21/commands/get-field-relation) | 21-partial | Relation settings; overlap with GET RELATION PROPERTIES, prefer current documented API. | U | R2/X |
| [TRIGGER PROPERTIES](https://developer.4d.com/docs/21/commands/trigger-properties) | 21-partial | Trigger-execution context output, not static trigger inventory. | PROCESS | X |
| [Records in table](https://developer.4d.com/docs/21/commands/records-in-table) | 21-partial | Integer aggregate count, not selection/private records. Concurrency consistency must be tested. | ENGINE | R2 |
| [Table fragmentation](https://developer.4d.com/docs/21/commands/table-fragmentation) | 21 | Real logical-record fragmentation percentage; not index fragmentation or physical disk fragmentation. Cost not benchmarked. | ENGINE TS | R3 initially |
| [Get external data path](https://developer.4d.com/docs/21/commands/get-external-data-path) | 21 | Field external-storage path text; never expose path. | ENGINE | R1 |
| [Get document size](https://developer.4d.com/docs/21/commands/get-document-size) | unknown | Open-document size scalar; prefer metadata without opening new handles, verify units. | OWNED | R1/X |
| [GET DOCUMENT PROPERTIES](https://developer.4d.com/docs/21/commands/get-document-properties) | 21-partial | Filesystem date/time/status metadata; fixed approved paths only. | HOST | R2 |
| [VOLUME LIST](https://developer.4d.com/docs/21/commands/volume-list) | 21-partial | Mounted volume arrays; no mount labels exported. | HOST | R2 |
| [VOLUME ATTRIBUTES](https://developer.4d.com/docs/21/commands/volume-attributes) | 21-partial | Capacity/free-space metadata; verify output units before normalization. | HOST | R2 |
| [EXPORT STRUCTURE](https://developer.4d.com/docs/21/commands/export-structure) | 21 | Exports schema XML; can inspect index metadata locally if required, but do not return XML or persist private schema. Potentially large. | ENGINE U | R3 |
| [Export structure file](https://developer.4d.com/docs/21/commands/export-structure-file) | 21 | Writes exported structure/project material; unnecessary for basic metadata. | U | A1/X |
| [CREATE INDEX](https://developer.4d.com/docs/21/commands/create-index) | 21; overloads partial | Changes index definitions, expensive rebuild; beta vector constants NOT inferred available in LTS. | ENGINE U | A3 |
| [DELETE INDEX](https://developer.4d.com/docs/21/commands/delete-index) | 21 | Removes index; performance/consistency impact. | ENGINE U | A3 |
| [SET INDEX](https://developer.4d.com/docs/21/commands/set-index) | 21; overloads partial | Changes field index state/type; beta syntax is not runtime proof. | ENGINE U | A3 |
| [PAUSE INDEXES](https://developer.4d.com/docs/21/commands/pause-indexes) | 21 | Disables/suspends table index maintenance. | ENGINE U | A2/A3 |
| [RESUME INDEXES](https://developer.4d.com/docs/21/commands/resume-indexes) | 21 | Resumes/rebuilds indexes, potentially expensive. | ENGINE U | A2/A3 |
| [IMPORT STRUCTURE](https://developer.4d.com/docs/21/commands/import-structure) | 21 | Alters schema from XML. Never accept uploaded arbitrary schema. | ENGINE U | A3 |
| [REGENERATE MISSING TABLE](https://developer.4d.com/docs/21/commands/regenerate-missing-table) | 21 | Recovery operation on missing table. | ENGINE U | A3 |
| [SET EXTERNAL DATA PATH](https://developer.4d.com/docs/21/commands/set-external-data-path) | 21 | Changes external field storage configuration. | ENGINE U | A3 |
| [RELOAD EXTERNAL DATA](https://developer.4d.com/docs/21/commands/reload-external-data) | 21 | Reloads externally stored field data; record-context operation, not disk health. | U | A2/X |
| [TRUNCATE TABLE](https://developer.4d.com/docs/21/commands/truncate-table) | 21-partial | Removes table data. | ENGINE U | A3 |

`GET INDEXES` was not found as a classic catalog command and is NOT proposed. In 21 LTS use documented field indexed flags, optionally carefully scoped structure metadata; neither is equivalent to later `DataClass.getIndexes()` or a universal index-build progress API.

## Backup, journal, maintenance and lifecycle

The [21 Backup theme](https://developer.4d.com/docs/21/commands/theme/Backup) confirms the backup/journal family. Paths and diagnostic contents remain private.

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [BACKUP INFO](https://developer.4d.com/docs/21/commands/backup-info) | 21 | Selector outputs: last/next backup Date+Time; last status integer+text; last duration **milliseconds** and begin timestamp. Redact status text if paths/details embedded. | ENGINE COOP; validate host/server backup config | R1, 60 seconds |
| [RESTORE INFO](https://developer.4d.com/docs/21/commands/restore-info) | 21 | Selector-dependent output parameters for restore state; exact selector shapes must be completed. | U | R1 |
| [Log file](https://developer.4d.com/docs/21/commands/log-file) | 21 | Journal path text; derive configured/existence/size only. Not debug log path. | ENGINE U | R1 |
| [Last update log path](https://developer.4d.com/docs/21/commands/last-update-log-path) | 21 | Update log path text; derive bounded scalar metadata, no contents. | HOST U | R1 |
| [CHECK LOG FILE](https://developer.4d.com/docs/21/commands/check-log-file) | 21 | Journal consistency check; exact UI/result/writing behavior not established. | U | R3; manual only |
| [LOG FILE TO JSON](https://developer.4d.com/docs/21/commands/log-file-to-json) | 21 | Writes journal conversion files; exposes application records/changes. | U | A1/X; prohibited dashboard export |
| [BACKUP](https://developer.4d.com/docs/21/commands/backup) | 21 | Starts backup, writes archives and may block activity. Not a low-risk first action. | ENGINE U | A2 |
| [New log file](https://developer.4d.com/docs/21/commands/new-log-file) | 21 | Rolls journal, returns path; modifies durability/recovery chain. | ENGINE U | A2 |
| [SELECT LOG FILE](https://developer.4d.com/docs/21/commands/select-log-file) | 21 | Changes selected journal configuration. | ENGINE U | A3 |
| [INTEGRATE MIRROR LOG FILE](https://developer.4d.com/docs/21/commands/integrate-mirror-log-file) | 21 | Integrates journal operations; writes/replays application data. | U | A3 |
| [RESTORE](https://developer.4d.com/docs/21/commands/restore) | 21 | Restores archive/data to destination, not observation. | U | A3 |
| [VERIFY CURRENT DATA FILE](https://developer.4d.com/docs/21/commands/verify-current-data-file) | 21 | Checks current data records/indexes; callback/log options, potentially heavy I/O. | ENGINE U | R3; maintenance only |
| [VERIFY DATA FILE](https://developer.4d.com/docs/21/commands/verify-data-file) | 21 | Checks nominated data/structure file; `Verify indexes` physical index consistency differs from `Verify all` record-linked checks. Current/offline eligibility is parameter/context-dependent. | U | R3; no arbitrary path, no routine polling |
| [Compact data file](https://developer.4d.com/docs/21/commands/compact-data-file) | 21 | Creates/reorganizes data-file output; returned path, offline/current restrictions and recovery requirements. | U | A3 |
| [OPEN DATA FILE](https://developer.4d.com/docs/21/commands/open-data-file) | 21 | Switches data file. | U | A3 |
| [CREATE DATA FILE](https://developer.4d.com/docs/21/commands/create-data-file) | 21 | Creates data file. | U | A3 |
| [OPEN DATABASE](https://developer.4d.com/docs/21/commands/open-database) | 21 | Opens/switches database/application. | U | A3 |
| [RELOAD PROJECT](https://developer.4d.com/docs/21/commands/reload-project) | 21 | Reloads project code/configuration; production behavior may change. | U | A2 |
| [SET UPDATE FOLDER](https://developer.4d.com/docs/21/commands/set-update-folder) | 21 | Configures client update distribution; path/code supply-chain risk. | U | A3 |
| [RESTART 4D](https://developer.4d.com/docs/21/commands/restart-4d) | 21 | Restarts application with optional timing/message; disconnects/in-flight work. Exact time units need contract completion. | HOST U | A2 |
| [QUIT 4D](https://developer.4d.com/docs/21/commands/quit-4d) | 21 | Stops application, optional time; no generic remote shutdown endpoint. | HOST U | A2 |

## Configuration selectors: separate read/write contracts

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Get database parameter](https://developer.4d.com/docs/21/commands/get-database-parameter) | 21 | Real numeric output or optional Text out parameter; selector-specific units/scope/thread safety/persistence. Whitelist selectors, not arbitrary numeric IDs. | Selector-dependent; overall COOP with explicitly documented TS selectors | R1 |
| [SET DATABASE PARAMETER](https://developer.4d.com/docs/21/commands/set-database-parameter) | 21 | Changes selected parameter; separate type, range, units, persistence and sign semantics. Not all GET selectors writable. | Selector-dependent; overall COOP with TS exceptions | A2 |
| [Get database localization](https://developer.4d.com/docs/21/commands/get-database-localization) | 21 | Language/localization text with host/component options. | HOST U | R1 |
| [SET DATABASE LOCALIZATION](https://developer.4d.com/docs/21/commands/set-database-localization) | 21 | Changes localization behavior; not health maintenance. | U | A2/X |

Useful selector sub-inventory (all must inherit the source page and their exact execution/persistence subsection):

| Selector | LTS evidence | Safe information / operational caveat |
|---|---|---|
| Is current database a project (112) | 21 | Read-only 0/1 current DB architecture. |
| Is host database a project (113) | 21 | Read-only 0/1 host DB architecture. |
| Is host database writable (117) | 21 | Read-only 0/1 project/structure writability, NOT data-file write permission. |
| Libldap version (114) | 21 | Current-machine library version; read only. |
| Libsasl version (115) | 21 | Current-machine library version; read only. |
| Libzip version (120) | 21 | Current-machine library version; read only. |
| OpenSSL version (94) | 21 | Current-machine library version; read only. |
| Cache flush periodicity (95) | 21 | Inspected GET and SET 21 HTML BOTH say seconds, >1, standalone/Server, thread-safe, session-only override. Do not invent a unit mismatch for this selector. |
| Cache unload minimum size (66) | 21-partial | Verify selector units versus SET CACHE SIZE minFreeSize; do not equate them without contract. |
| 4D Server timeout (13) | 21-partial | SET description says minutes; sign selects persistent global versus temporary process behavior, zero means no timeout. GET-unit equivalence not independently established; no raw GET-to-SET round trip. |
| 4D Remote mode timeout (14) | 21 | Legacy-network-only; ignored under ServerNet. Do not display as effective ServerNet timeout. |
| Idle connections timeout (54) | 21 | Seconds; sign distinguishes new versus existing/current-process connections; network behavior changes require Server/client tests. |
| Remote connection sleep timeout (98) | 21 | Seconds; Server checks every 5 minutes, so observed release may lag by 300 seconds. |
| 4D Server log recording (28) | 21-partial | Server/remote scope with special remote behavior; bounded read first, writes disabled. |
| Client log recording (45) | 21-partial | Client-local log state; not Server logging. |
| Debug log recording (34) | 21-partial | Logging mode; enabling causes disk I/O and sensitive logs. |
| Current process debug log recording (111) | 21 | Current-process only; not all-Server debug log state. |
| Diagnostic log recording (79) | 21-partial | Logging enabled/mode state; manual bounded changes only. |
| Diagnostic log level (86) | 21-partial | Level enum, not event count. |
| Log command list (80) | 21-partial | Filter/config text; do not expose code names or accept arbitrary lists. |
| Circular log limitation (90) | 21-partial | Verify selector unit/range before exposing size limit. |
| Pause logging (121) | 21-partial | Mutating setter can hide audit/diagnostic evidence; not first maintenance action. |
| SQL Server Port ID (88) | 21 | Numeric port; not proof SQL service is running. |
| Client Server port ID (35) | 21-partial | Numeric configured port; effective runtime values require Application info. |
| Server base process stack size (53) | 21 | Bytes, preemptive system process stack; no dynamic tuning initially. |
| Min TLS version (105) | 21-partial | TLS enum; don't map numeric IDs without constants table. |
| SSL cipher list (64) | 21 | Text out parameter with numeric return 0; do not treat 0 as disabled TLS. |
| Use legacy network layer (87) | 21-partial | Config flag; runtime transport comes from Application info. |
| Table sequence number (31) | 21 | Last number used, not row count. Setting changes subsequent autoincrement -> A3, never maintenance. |
| Times inside objects (109) | 21 | Seconds vs milliseconds conversion setting; ORDA/SQL still use seconds. Not universal timestamp normalization. |
| TCPUDP log recording (131) | 21-partial | Source presence alone does not establish every selector behavior; network logs sensitive. |

Important unit policy: GET/SET parameter and option contracts can differ by API/selector, and the corpus does not establish a universal round-trip unit invariant. Store `readUnit`, `writeUnit`, range, scope and persistence separately. The inspected 21 cache-flush selector documents matching seconds; the Server-timeout read-unit issue remains unresolved. A claimed specific mismatch requires a specific official source, not analogy. Debug standard mode uses milliseconds, tabbed mode microseconds; Process info CPU fraction differs from Application info percent.

## Web, REST, SQL and network services

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [WEB Get server info](https://developer.4d.com/docs/21/commands/web-get-server-info) | 21 | Runtime object including SOAP; effective settings may differ from WEB GET OPTION. **withCache=False/omitted** initially: cache description can be very large. Redact IPs/paths/cookie identifiers. | WEB; exact thread U | R1/R2 |
| [WEB Is server running](https://developer.4d.com/docs/21/commands/web-is-server-running) | 21-partial | Boolean selected/default web server running state. | WEB | R1 |
| [WEB GET STATISTICS](https://developer.4d.com/docs/21/commands/web-get-statistics) | 21-partial | Web cache/statistics out parameters; exact units/coverage require full contract. | WEB | R2 |
| [WEB GET OPTION](https://developer.4d.com/docs/21/commands/web-get-option) | 21-partial | Selector-dependent numeric/text/config values; not guaranteed effective runtime state. | WEB, selector/thread U | R1 |
| [WEB Server](https://developer.4d.com/docs/21/commands/web-server) | 21 | `4D.WebServer` object for host/component selection. | WEB | R1 |
| [WEB Server list](https://developer.4d.com/docs/21/commands/web-server-list) | 21-partial | Collection of host/component web server objects; aggregate by approved role, not arbitrary names. | WEB | R2 |
| [WEB Is secured connection](https://developer.4d.com/docs/21/commands/web-is-secured-connection) | 21-partial | Boolean current request's secure connection; not global TLS configuration. | WEB/current request | R1 |
| [WEB Get current session ID](https://developer.4d.com/docs/21/commands/web-get-current-session-id) | 21-partial | Session identifier; never return it to dashboard telemetry. | WEB | X |
| [WEB LEGACY GET SESSION EXPIRATION](https://developer.4d.com/docs/21/commands/web-legacy-get-session-expiration) | unknown | Legacy-session expiration; not scalable session contract. | WEB legacy U | R1/X |
| [WEB SET OPTION](https://developer.4d.com/docs/21/commands/web-set-option) | 21-partial | Selector-specific configuration change; separate GET/SET units and restart applicability. | WEB U | A2 |
| [WEB START SERVER](https://developer.4d.com/docs/21/commands/web-start-server) | 21-partial | Starts server; port/certificate/session/security preconditions. | WEB U | A2 |
| [WEB STOP SERVER](https://developer.4d.com/docs/21/commands/web-stop-server) | 21-partial | Stops server, can remove dashboard's own transport. | WEB U | A2 |
| [WEB SET ROOT FOLDER](https://developer.4d.com/docs/21/commands/web-set-root-folder) | 21-partial | Changes served filesystem scope. | WEB U | A2 |
| [WEB SET HOME PAGE](https://developer.4d.com/docs/21/commands/web-set-home-page) | 21-partial | Changes default web route/page. | WEB U | A2/X |
| [WEB LEGACY CLOSE SESSION](https://developer.4d.com/docs/21/commands/web-legacy-close-session) | unknown | Invalidates legacy web session; not general scalable-session disconnect. | WEB U | A2 |
| [SOAP Get info](https://developer.4d.com/docs/21/commands/soap-get-info) | 21-partial | SOAP server/request context info; exact scope/shape unresolved; publish counters only. | WEB U | R2 |
| [SOAP REJECT NEW REQUESTS](https://developer.4d.com/docs/21/commands/soap-reject-new-requests) | unknown | Admission-control mutation for SOAP, not all HTTP/REST. | WEB U | A2 |
| [HTTP GET OPTION](https://developer.4d.com/docs/21/commands/http-get-option) | 21-partial | Outbound HTTP-client options, not web-server health. | PROCESS/HOST U | R1/X |
| [HTTP Get certificates folder](https://developer.4d.com/docs/21/commands/http-get-certificates-folder) | 21-partial | Outbound-client certificate folder path; derive presence only. | HOST U | R1/X |
| [HTTP SET OPTION](https://developer.4d.com/docs/21/commands/http-set-option) | 21-partial | Outbound-client configuration mutation. | U | A2/X |
| [HTTP SET CERTIFICATES FOLDER](https://developer.4d.com/docs/21/commands/http-set-certificates-folder) | 21-partial | Changes outbound TLS trust/certificates scope. | U | A2/X |
| [SQL GET OPTION](https://developer.4d.com/docs/21/commands/sql-get-option) | 21 | Selector output for current SQL context; exact selector units/type U. | PROCESS | R1 |
| [SQL GET LAST ERROR](https://developer.4d.com/docs/21/commands/sql-get-last-error) | 21 | Error codes/text/ODBC/SQLServer outputs; aggregate codes only, no full driver error text. | PROCESS | R1 |
| [SQL Get current data source](https://developer.4d.com/docs/21/commands/sql-get-current-data-source) | 21 | Text data-source identity; do not expose DSN/connection identity. | PROCESS | R1/X |
| [SQL GET DATA SOURCE LIST](https://developer.4d.com/docs/21/commands/sql-get-data-source-list) | 21 | Source-name/driver arrays; local driver count only, DSNs private. | HOST/PROCESS U | R2 |
| [SQL SET OPTION](https://developer.4d.com/docs/21/commands/sql-set-option) | 21 | SQL connection/context option mutation. | PROCESS U | A2 |
| [START SQL SERVER](https://developer.4d.com/docs/21/commands/start-sql-server) | 21 | Starts SQL service; port/TLS/access group deployment prerequisites. | U; validate Server | A2 |
| [STOP SQL SERVER](https://developer.4d.com/docs/21/commands/stop-sql-server) | 21 | Stops SQL service and interrupts clients. | U; validate Server | A2 |
| [SQL LOGIN](https://developer.4d.com/docs/21/commands/sql-login) | 21 | Opens authenticated SQL context; credential operation, not telemetry. | PROCESS | A2/X |
| [SQL LOGOUT](https://developer.4d.com/docs/21/commands/sql-logout) | 21 | Closes current SQL connection/context. | PROCESS | A2/X |
| [SQL EXECUTE](https://developer.4d.com/docs/21/commands/sql-execute) | 21 | Arbitrary SQL execution; expressly excluded dashboard control. | PROCESS | A3/X |
| [SQL EXECUTE SCRIPT](https://developer.4d.com/docs/21/commands/sql-execute-script) | 21 | Executes nominated script; arbitrary code/data mutation. | U | A3/X |
| [SQL EXPORT DATABASE](https://developer.4d.com/docs/21/commands/sql-export-database) | 21 | Exports application data to disk. | U | A3/X |
| [SQL EXPORT SELECTION](https://developer.4d.com/docs/21/commands/sql-export-selection) | 21 | Exports private selected data. | PROCESS | A3/X |
| [GET /rest/$info](https://developer.4d.com/docs/21/REST/info) | 21; supplemental non-IR REST API | Object: cacheSize/usedCache, entitySetCount, entity-set/session/progress/privileges collections. Aggregate only; no IDs, users, dataClass labels without approval. Permissions/administration exposure must be verified separately. | WEB/REST Server deployment | R2/R3 |

HTTP request bodies/headers/variables, web response sending, SOAP client calls, mail/LDAP connectivity and arbitrary TCP/UDP/HTTP probes are excluded as business transport or credential/private payload operations. A configured port is not a verified listening service. Do not add OS socket scans, external reachability probes or access-key tests as inferred 4D APIs.

The [21 TLS overview](https://developer.4d.com/docs/21/Admin/tls), [web administration](https://developer.4d.com/docs/21/Admin/webAdmin), [ORDA privileges](https://developer.4d.com/docs/21/ORDA/privileges) and [HTTP handlers](https://developer.4d.com/docs/21/WebServer/http-request-handler) are supporting contracts, not generic admin endpoints. Custom HTTP handlers bypass normal built-in authentication/connection processing; their own authentication/authorization is mandatory. WebAdmin/Data Explorer permission is not equivalent to the dashboard's operator role.

## Security and users/groups

| Exact API / official source | Availability | Result / units and caveat | Execution | Semantics |
|---|---|---|---|---|
| [Data file encryption status](https://developer.4d.com/docs/21/commands/data-file-encryption-status) | 21 | Object for nominated data/structure file; return encryption-enabled/key-required booleans only after checking contract. No key material. | U; prefer current ds.encryptionStatus | R2 |
| [Current user](https://developer.4d.com/docs/21/commands/current-user) | 21-partial | Account/alias text; authorization must distinguish real account from alias. No names in telemetry. | PROCESS | R1/X |
| [Current system user](https://developer.4d.com/docs/21/commands/current-system-user) | 21-partial | OS identity text; privacy-sensitive, exclude value. | HOST | X |
| [Current client authentication](https://developer.4d.com/docs/21/commands/current-client-authentication) | 21 | Windows SSO asks domain controller for authenticated login; optional outputs characterize authentication. Not a harmless cross-platform identity scalar; no identity/domain returned. | Windows SSO client/server domain deployment | R3/X |
| [Get default user](https://developer.4d.com/docs/21/commands/get-default-user) | 21-partial | Default-account metadata; publish presence only, not user identity. | U | R1 |
| [GET USER LIST](https://developer.4d.com/docs/21/commands/get-user-list) | 21 | Parallel name/ID arrays; count only. Explicit access-privilege/password-system contention errors. | U COOP | R2 |
| [GET USER PROPERTIES](https://developer.4d.com/docs/21/commands/get-user-properties) | 21 | User configuration/membership outputs; login statistics/group-owner features may be binary-only. Never password/name/email outputs. Explicit access privilege errors. | U COOP | R2 |
| [GET GROUP LIST](https://developer.4d.com/docs/21/commands/get-group-list) | 21 | Name/ID arrays; project IDs dynamically allocated at startup from 15001. Explicit access-privilege/password-system contention errors. | U COOP | R2 |
| [GET GROUP PROPERTIES](https://developer.4d.com/docs/21/commands/get-group-properties) | 21 | Membership output; owner always 0 in project DB. Explicit access errors. | U COOP | R2 |
| [Get group access](https://developer.4d.com/docs/21/commands/get-group-access) | 21 | Collection of current-session account's group names, empty if none. Not a global role inventory. | PROCESS TS | R1 |
| [User in group](https://developer.4d.com/docs/21/commands/user-in-group) | 21 | Boolean membership; expects account, not alias. | PROCESS COOP | R1 |
| [Is user deleted](https://developer.4d.com/docs/21/commands/is-user-deleted) | 21-partial | Boolean for account identifier; count approved account state only. | U | R1 |
| [Get plugin access](https://developer.4d.com/docs/21/commands/get-plugin-access) | 21-partial | Plugin access-setting metadata, not license proof. | U | R1 |
| [Set user properties](https://developer.4d.com/docs/21/commands/set-user-properties) | 21 | Creates/changes user/memberships; explicit access-privilege errors, binary-only options ignored in projects. | U COOP | A2 |
| [Set group properties](https://developer.4d.com/docs/21/commands/set-group-properties) | 21-partial | Changes group/member definitions; exact privilege rule needs source completion. | U | A2 |
| [DELETE USER](https://developer.4d.com/docs/21/commands/delete-user) | 21-partial | Removes/deletes user configuration. | U | A3 |
| [CHANGE CURRENT USER](https://developer.4d.com/docs/21/commands/change-current-user) | 21-partial | Changes runtime identity; not a dashboard impersonation endpoint. | PROCESS | A2/X |
| [CHANGE PASSWORD](https://developer.4d.com/docs/21/commands/change-password) | 21-partial | Credential mutation; no password UI/API in this roadmap. | U | A2/X |
| [SET USER ALIAS](https://developer.4d.com/docs/21/commands/set-user-alias) | 21-partial | Changes display identity, not security entitlement. | PROCESS | A2/X |
| [SET GROUP ACCESS](https://developer.4d.com/docs/21/commands/set-group-access) | 21-partial | Changes current account/session group access. | U | A2 |
| [SET PLUGIN ACCESS](https://developer.4d.com/docs/21/commands/set-plugin-access) | 21-partial | Changes plugin authorization. | U | A2 |
| [USERS TO BLOB](https://developer.4d.com/docs/21/commands/users-to-blob) | 21-partial | Exports access configuration; sensitive, no dashboard export. | U | A3/X |
| [BLOB TO USERS](https://developer.4d.com/docs/21/commands/blob-to-users) | 21-partial | Imports/replaces access configuration. | U | A3/X |
| [Discover data key](https://developer.4d.com/docs/21/commands/discover-data-key) | 21 | Discovers/provides key material to engine; not observational status. | U | A2/X |
| [Register data key](https://developer.4d.com/docs/21/commands/register-data-key) | 21 | Registers passphrase/key for decryption. | U | A2/X |
| [New data key](https://developer.4d.com/docs/21/commands/new-data-key) | 21 | Returns key object from passphrase. | U | A3/X |
| [Encrypt data file](https://developer.4d.com/docs/21/commands/encrypt-data-file) | 21 | Rewrites/encrypts/decrypts data-file output; paths/passphrases/key objects and archive recovery. | U | A3 |

The [21 users/groups guide](https://developer.4d.com/docs/21/Users/editing) says project user/group access control is effective on 4D Server; single-user projects identify users as Designer. A standalone authorization test is therefore not sufficient for real Server operator access. Desktop groups and ORDA web privileges must not be conflated.

Secured Protocol keypair/certificate-request generation, CryptoKey operations, encryption/decryption BLOBs and digest utilities are excluded: they process secrets/payloads rather than provide useful operational information.

## OOP datastore and dataclass records

Source aliases in these rows resolve to exact official pages:

- **DS**: https://developer.4d.com/docs/21/API/DataStoreClass
- **DC**: https://developer.4d.com/docs/21/API/DataClassClass
- **E**: https://developer.4d.com/docs/21/API/EntityClass

Append the lowercase member heading, e.g. DS#encryptionstatus. Captured 21 headings/summary corroborate the listed DS/DC members; not every runtime restriction was fully read.

| Exact member / source | Availability | Shape / units / privacy | Execution | Semantics |
|---|---|---|---|---|
| DataStore.getInfo() / DS#getinfo | 21 | Object with type/networked/localID and remote details; expose type/networked only. | Datastore instance, local/remote semantics | R1 |
| DataStore.locked() / DS#locked | 21 | Boolean local datastore lock, also True for backup/VSS locks; does not identify owner or prove dashboard owns lock. | ENGINE | R1 |
| DataStore.encryptionStatus() / DS#encryptionstatus | 21 | Object current-file/per-table encryption status; aggregate booleans/counts, no keys. | ENGINE; remote eligibility U | R2 |
| DataStore.isAdminProtected() / DS#isadminprotected | 21 | Boolean Data Explorer access-disabled state for working session; not generic app authorization. | ENGINE/U | R1 |
| DataStore.getGlobalStamp() / DS#getglobalstamp | 21 | Real modification stamp, not timestamp/row count; avoid unsafe JSON integer precision assumptions. | Datastore instance U | R1 |
| DataStore.getAllRemoteContexts() / DS#getallremotecontexts | 21 | Collection optimization contexts; aggregate count/approved scalar metadata only. | Datastore optimization context U | R2 |
| DataStore.getRemoteContextInfo() / DS#getremotecontextinfo | 21 | Object for specified optimization context; not records/attributes values. | Context-specific U | R2 |
| DataStore.getRequestLog() / DS#getrequestlog | 21 | ORDA request log collection; contains requests/literals/paths; do not export raw. Requires preexisting logging and exact retrieval semantics review. | Calling client or Server machine | R3 |
| DataStore.startRequestLog() / DS#startrequestlog | 21 | Starts ORDA request logging on caller machine, may allocate memory/write disk. | Client or Server | A1; bounded duration/size only after review |
| DataStore.stopRequestLog() / DS#stoprequestlog | 21 | Stops ORDA request logging on caller machine; only integration-owned logging session. | Client or Server | A1 |
| DataStore.clearAllRemoteContexts() / DS#clearallremotecontexts | 21 | Clears optimization-context attributes; affects performance. | Context-specific U | A2 |
| DataStore.setRemoteContextInfo() / DS#setremotecontextinfo | 21 | Alters optimization-context settings; schema/performance sensitive. | Context-specific U | A2 |
| DataStore.setAdminProtection() / DS#setadminprotection | 21 | Disables web-admin/Data Explorer data access even for WebAdmin session; persists immediately on disk. Not interchangeable with endpoint authorization. | ENGINE/U | A2 |
| DataStore.flushAndLock() / DS#flushandlock | 21 | Flushes local cache and freezes writes; nested locks require same number of unlocks in same process; backup/VSS interplay. | ENGINE, same-process lifecycle | A2/A3; not generic lock button |
| DataStore.unlock() / DS#unlock | 21 | Removes own write lock set in SAME process; does not unlock arbitrary backup/VSS/other-process locks. | ENGINE, same process as acquisition | A2 |
| DataStore.setGlobalStamp() / DS#setglobalstamp | 21 | Changes global modification stamp; can affect synchronization. | Datastore U | A3 |
| DataStore.provideDataKey() / DS#providedatakey | 21 | Supplies encryption key/passphrase; secrets outside dashboard scope. | U | A3/X |
| DataStore.startTransaction() / DS#starttransaction | 21 | Starts transaction for this datastore in current process. | PROCESS | A2/X |
| DataStore.cancelTransaction() / DS#canceltransaction | 21 | Cancels current-process transaction. | PROCESS | A3/X |
| DataStore.validateTransaction() / DS#validatetransaction | 21 | Commits current-process transaction. | PROCESS | A3/X |
| DataStore.makeSelectionsAlterable() / DS#makeselectionsalterable | 21 | Changes default selection behavior across app datastores; compatibility migration, not maintenance. | Application | A2/X |
| DataClass.getInfo() / DC#getinfo | 21 | Object `{exposed,name,primaryKey,tableNumber}`; scalar exposure/count/approved schema IDs only. | Dataclass instance local/remote | R1 |
| DataClass.getCount() / DC#getcount | 21 | Integer entity count; possible network roundtrip and concurrent-write consistency; no enumeration. | Dataclass instance local/remote | R2 |
| DataClass.getDataStore() / DC#getdatastore | 21 | Datastore object; internal routing helper, never raw serialization. | Dataclass instance | X |
| DataClass.attributeName / DC#attributename | 21 | Attribute description object; safe type/index/schema metadata only, no entity values. | Dataclass instance | R2 |
| DataClass.getRemoteCache() / DC#getremotecache | 21 | Object containing ORDA cache **contents**; aggregate metrics only if safe, no entities/keys/values. | Remote-cache context U | R3 |
| DataClass.clearRemoteCache() / DC#clearremotecache | 21 | Empties dataclass ORDA cache; local owner/client cache semantics must be verified, can increase network load. | Remote-cache context U | A1/A2 |
| DataClass.setRemoteCacheSettings() / DC#setremotecachesettings | 21 | Changes ORDA cache settings; exact timeout units/ranges/scope U. | Remote-cache context U | A2 |
| DataClass.getIndexes() / https://developer.4d.com/docs/API/DataClassClass#getindexes | later: 21 R5 | Collection of index objects; absent from inspected 21 heading set. No LTS baseline implementation. | Dataclass U | R2, gated later feature |
| Entity.getStamp() / E#getstamp | 21-partial | Record-specific modification stamp; no arbitrary records loaded for telemetry. | Existing entity | X |
| Entity.isNew() / E#isnew | 21-partial | Boolean record context, not DB-wide diagnostic. | Existing entity | X |
| Entity.touched() / E#touched | 21-partial | Boolean unsaved entity changes. | Existing entity | X |
| Entity.touchedAttributes() / E#touchedattributes | 21-partial | Attribute names; private record activity, excluded. | Existing entity | X |
| Entity.lock() / E#lock | 21-partial | Pessimistic record lock; mutating ownership, not global lock query. | Existing entity PROCESS | A2/X |
| Entity.unlock() / E#unlock | 21-partial | Releases entity lock; not universal unlock. | Existing entity PROCESS | A2/X |

`DataClass.all/query/get/fromCollection`, Entity CRUD/navigation/serialization, EntitySelection queries/aggregates and user datastore/class/entity/selection methods are excluded. Even a query can change selections/cache/locks or disclose private records. No arbitrary application `authentify` method is assumed; ORDA authorization design is a separate contract.

## OOP session records

All **S** sources: https://developer.4d.com/docs/21/API/SessionClass, with indicated heading. Session object is current-session context, not an administrative object for every connected user. Web privilege enforcement is web/REST-only; the class supports desktop sessions but that does not establish equivalent desktop access control.

| Exact member / source | Availability | Shape / units / privacy | Execution | Semantics |
|---|---|---|---|---|
| Session.info / S#info | 21 | Object describing desktop/web session. Redact identity/network/UUID fields; later `unreachableSince` is not LTS baseline. | Current session | R1 |
| Session.id / S#id | 21 | Text UUID; do not export raw. | Current session | X |
| Session.userName / S#username | 21 | Text identity; do not export. | Current session | X |
| Session.storage / S#storage | 21 | Shared object application data; no inspection. | Current session/shared processes | X |
| Session.expirationDate / S#expirationdate | 21 | Web-session date/time; expose derived expiry interval only after clock/type verification. | Web user session only | R1 |
| Session.idleTimeout / S#idletimeout | 21 | Web inactivity timeout **minutes**; reads and writes must be distinguished. | Web user session | R1 read / A2 write |
| Session.getPrivileges() / S#getprivileges | 21 | Collection of SESSION privilege names; **does not include promoted process privileges**. Return allowed-action booleans, not raw names. | Current session; behavior session-type-dependent | R1 |
| Session.hasPrivilege() / S#hasprivilege | 21 | Boolean for named SESSION privilege; does not imply promoted privilege coverage. | Current session; behavior session-type-dependent | R1 |
| Session.isGuest() / S#isguest | 21 | Boolean guest state; desktop True if no privileges per compatibility note, not proof of unauthenticated desktop identity. | Current session | R1 |
| Session.setPrivileges() / S#setprivileges | 21 | Boolean result assigning session privileges/settings; not automatic authentication, must follow verified login policy. | Web enforced; desktop semantics differ | A2 |
| Session.clearPrivileges() / S#clearprivileges | 21 | Clears privileges/session security state. | Current session, type-dependent | A2 |
| Session.promote() / S#promote | 21 | Integer promoted privilege ID, process/function duration; requires ORDA promotion permission policy. | Current WEB process | A2; never generic privilege escalation |
| Session.demote() / S#demote | 21 | Removes previously promoted privilege by ID; use owned LIFO scope. | Same relevant WEB process | A1/A2 |
| Session.createOTP() / S#createotp | 21 | Creates session-restoration one-time code/material; never telemetry. | Current session, exact allowed types U | A2/X |
| Session.restore() / S#restore | 21 | Boolean; replaces current web session with original token session and restores storage/privileges. | WEB | A2/X |
| Session.quotas / https://developer.4d.com/docs/API/SessionClass#quotas | later: 21 R4 | Quota object, absent inspected 21 page; NOT baseline. | U | R2/A2 depending operation |

## OOP WebServer records

All **W** sources: https://developer.4d.com/docs/21/API/WebServerClass with lowercase member heading. Unless otherwise stated, availability is **21-partial**: named configuration member is in the 21 page/class family, but complete getter/setter, unit, startup applicability and thread contracts need per-member verification. Do not assume a writable property is read-only merely because telemetry reads it.

All W records execute in **WEB** context for the selected host/component server, with unspecified thread safety and required real web/Server deployment. Read profile R1 unless a row says R2; any property assignment is A2, explicit operator-only and not part of the first release. Specific built-in privilege requirement is unresolved; dashboard permission is mandatory.

| Exact member / source | Availability | Allowed scalar metadata / units; sensitive exclusions | Semantics override |
|---|---|---|---|
| WebServer.isRunning / W#isrunning | 21 | Boolean running state. | R1 |
| WebServer.name / W#name | 21-partial | Private server label; approved role/count only. | R1 |
| WebServer.HTTPEnabled / W#httpenabled | 21-partial | Boolean HTTP flag. | R1 / A2 assignment |
| WebServer.HTTPPort / W#httpport | 21-partial | Numeric port. | R1 / A2 assignment |
| WebServer.HTTPSEnabled / W#httpsenabled | 21-partial | Boolean HTTPS flag. | R1 / A2 assignment |
| WebServer.HTTPSPort / W#httpsport | 21-partial | Numeric port. | R1 / A2 assignment |
| WebServer.HTTPTrace / W#httptrace | 21-partial | Trace-enabled flag; enabling can expose payloads. | R1 / A2 assignment |
| WebServer.HTTPCompressionLevel / W#httpcompressionlevel | 21-partial | Compression enum/level, verify range. | R1 / A2 assignment |
| WebServer.HTTPCompressionThreshold / W#httpcompressionthreshold | 21-partial | Size threshold; unit requires confirmation. | R1 / A2 assignment |
| WebServer.HSTSEnabled / W#hstsenabled | 21-partial | Boolean HSTS flag. | R1 / A2 assignment |
| WebServer.HSTSMaxAge / W#hstsmaxage | 21-partial | HSTS lifetime; verify unit before normalization. | R1 / A2 assignment |
| WebServer.CORSEnabled / W#corsenabled | 21 | Boolean CORS state. | R1 / A2 assignment |
| WebServer.CORSSettings / W#corssettings | 21 | Collection allowed origins/methods: count only, no hosts. | R2 / A2 assignment |
| WebServer.minTLSVersion / W#mintlsversion | 21 | Integer TLS minimum enum. | R1 / A2 assignment |
| WebServer.cipherSuite / W#ciphersuite | 21 | Cipher-list text; policy classifier/count only. | R1 / A2 assignment |
| WebServer.perfectForwardSecrecy / W#perfectforwardsecrecy | 21-partial | Security setting; exact shape/read-write U. | R1 / A2 assignment |
| WebServer.openSSLVersion / W#opensslversion | 21-partial | Library version scalar. | R1 |
| WebServer.accessKeyDefined / W#accesskeydefined | 21 | Boolean key configured; NEVER read key. Not proof requester authenticated. | R1 |
| WebServer.certificateFolder / W#certificatefolder | 21 | Private folder path; configured/present booleans only. | R1 / A2 assignment |
| WebServer.IPAddressToListen / W#ipaddresstolisten | 21 | IP address text; bound-interface count/role only, no addresses. | R1 / A2 assignment |
| WebServer.rootFolder / W#rootfolder | 21-partial | Private served folder; no path. | R1 / A2 assignment |
| WebServer.defaultHomepage / W#defaulthomepage | 21-partial | Route text; presence only. | R1 / A2 assignment |
| WebServer.characterSet / W#characterset | 21 | Numeric/text encoding configuration; exact alternative type retained. | R1 / A2 assignment |
| WebServer.debugLog / W#debuglog | 21 | Integer request debug-log status; mode enum. | R1 / A2 assignment |
| WebServer.logRecording / W#logrecording | 21 | Integer request log recording mode. | R1 / A2 assignment |
| WebServer.maxRequestSize / W#maxrequestsize | 21 | Maximum incoming request **bytes**. | R1 / A2 assignment |
| WebServer.maxConcurrentProcesses / W#maxconcurrentprocesses | 21 | Integer; legacy-specific semantics, not scalable-session capacity. | R1 / A2 assignment |
| WebServer.maxSessions / W#maxsessions | 21 | Maximum simultaneous **legacy** sessions. | R1 / A2 assignment |
| WebServer.keepSession / W#keepsession | 21 | Boolean legacy session mode. | R1 / A2 assignment |
| WebServer.scalableSession / W#scalablesession | 21-partial | Scalable-session mode flag, must not mix with legacy limits. | R1 / A2 assignment |
| WebServer.inactiveSessionTimeout / W#inactivesessiontimeout | 21 | Legacy inactivity **minutes**, not scalable-session TTL. | R1 / A2 assignment |
| WebServer.inactiveProcessTimeout / W#inactiveprocesstimeout | 21-partial | Legacy process timeout; verify unit separately. | R1 / A2 assignment |
| WebServer.sessionCookieDomain / W#sessioncookiedomain | 21-partial | Private domain; configured boolean only. | R1 / A2 assignment |
| WebServer.sessionCookieName / W#sessioncookiename | 21-partial | Cookie name; do not export session identifiers. | R1 / A2 assignment |
| WebServer.sessionCookiePath / W#sessioncookiepath | 21-partial | Cookie path; presence only. | R1 / A2 assignment |
| WebServer.sessionCookieSameSite / W#sessioncookiesamesite | 21-partial | SameSite policy enum. | R1 / A2 assignment |
| WebServer.sessionIPAddressValidation / W#sessionipaddressvalidation | 21-partial | Validation flag; not permission to expose IPs. | R1 / A2 assignment |
| WebServer.handlers / W#handlers | 21 | Collection request handlers; count/allowed verbs only, not class/method/regex source. Custom handlers require their own auth. | R2 / A2 assignment |
| WebServer.rules / W#rules | 21 | Collection rules; count only, no route/source disclosure. | R2 / A2 assignment |
| WebServer.start() / W#start | 21; settings overloads partial | Start result/settings exact shape U; quota settings later-only. | A2 |
| WebServer.stop() / W#stop | 21 | Stops selected web server; may stop own dashboard access. | A2 |
| WebServer.quotas / https://developer.4d.com/docs/API/WebServerClass#quotas | later: 21 R5 | Quota manager object, absent inspected 21 page. | Not baseline |

## Owned filesystem, worker and network objects

These are supplemental integration health, not a global 4D/OS inventory. Native filesystem permissions apply; do not infer administrator access. Existing owned handles/objects only, approved fixed paths only; no recursive scan or arbitrary shell command. All exact thread constraints remain U.

| Exact member / official source | Availability | Shape / unit / scope | Semantics / cadence |
|---|---|---|---|
| Document.exists (inherited by File) / https://developer.4d.com/docs/21/API/Document#exists | 21-partial | Boolean fixed-file existence. Catalog declaring-class name differs from File instance API. | OWNED R1 |
| Document.size (File.size) / https://developer.4d.com/docs/21/API/Document#size | 21-partial | File bytes; no contents/path. | OWNED R1 |
| Document.modificationDate (File.modificationDate) / https://developer.4d.com/docs/21/API/Document#modificationdate | 21-partial | Date; combine only with documented modificationTime and clock zone. | OWNED R1 |
| Document.modificationTime (File.modificationTime) / https://developer.4d.com/docs/21/API/Document#modificationtime | 21-partial | Time; no arbitrary path. | OWNED R1 |
| Document.creationDate (File.creationDate) / https://developer.4d.com/docs/21/API/Document#creationdate | 21-partial | Date. | OWNED R1 |
| Document.creationTime (File.creationTime) / https://developer.4d.com/docs/21/API/Document#creationtime | 21-partial | Time. | OWNED R1 |
| Document.extension (File.extension) / https://developer.4d.com/docs/21/API/Document#extension | 21-partial | Text extension only, not basename/path. | OWNED R1 |
| Directory.exists (Folder.exists) / https://developer.4d.com/docs/21/API/Directory#exists | 21-partial | Boolean fixed-folder existence. | OWNED R1 |
| Directory.files() (Folder.files()) / https://developer.4d.com/docs/21/API/Directory#files | 21-partial | Collection file objects; bounded nonrecursive count only; aliases not resolved by default. | OWNED R2 |
| Directory.folders() (Folder.folders()) / https://developer.4d.com/docs/21/API/Directory#folders | 21-partial | Collection folder objects; bounded nonrecursive count only. | OWNED R2 |
| FileHandle.getSize() / https://developer.4d.com/docs/21/API/FileHandleClass#getsize | 21-partial | Bytes for existing integration-owned handle. | OWNED R1 |
| FileHandle.eof / https://developer.4d.com/docs/21/API/FileHandleClass#eof | 21-partial | Boolean owned stream status. | OWNED R1 |
| FileHandle.offset / https://developer.4d.com/docs/21/API/FileHandleClass#offset | 21-partial | Byte offset; writing property would alter reader position. | OWNED R1 read / A1 write |
| FileHandle.mode / https://developer.4d.com/docs/21/API/FileHandleClass#mode | 21-partial | Open-mode enum. | OWNED R1 |
| SystemWorker.pid / https://developer.4d.com/docs/21/API/SystemWorkerClass#pid | 21-partial | OS PID of owned Go CLI subprocess; not 4D process ID. | OWNED R1 |
| SystemWorker.exitCode / https://developer.4d.com/docs/21/API/SystemWorkerClass#exitcode | 21-partial | Integer exit code; availability before exit must be checked. | OWNED R1 |
| SystemWorker.terminated / https://developer.4d.com/docs/21/API/SystemWorkerClass#terminated | 21-partial | Boolean owned subprocess completion. | OWNED R1 |
| SystemWorker.errors / https://developer.4d.com/docs/21/API/SystemWorkerClass#errors | 21-partial | Error collection; code/count only, no command/stdout/stderr. | OWNED R1 |
| SystemWorker.timeout / https://developer.4d.com/docs/21/API/SystemWorkerClass#timeout | 21-partial | Timeout, exact unit and lifecycle U. | OWNED R1 read |
| SystemWorker.terminate() / https://developer.4d.com/docs/21/API/SystemWorkerClass#terminate | 21-partial | Terminates owned subprocess; never arbitrary OS PID kill. | OWNED A2 |
| HTTPAgent.requestsCount / https://developer.4d.com/docs/21/API/HTTPAgentClass#requestscount | 21-partial | Integer owned agent request count. | OWNED R1 |
| HTTPAgent.freeSocketsCount / https://developer.4d.com/docs/21/API/HTTPAgentClass#freesocketscount | 21-partial | Integer reusable sockets; not global host socket count. | OWNED R1 |
| HTTPRequest.terminated / https://developer.4d.com/docs/21/API/HTTPRequestClass#terminated | 21-partial | Boolean owned request completion. | OWNED R1 |
| HTTPRequest.errors / https://developer.4d.com/docs/21/API/HTTPRequestClass#errors | 21-partial | Error collection; no URL/header/body/token/identity export. | OWNED R1 |
| HTTPRequest.terminate() / https://developer.4d.com/docs/21/API/HTTPRequestClass#terminate | 21-partial | Cancels owned request, not remote service. | OWNED A1 |
| TCPListener.port / https://developer.4d.com/docs/21/API/TCPListenerClass#port | 21-partial | Integer owned listener port. | OWNED R1 |
| TCPListener.errors / https://developer.4d.com/docs/21/API/TCPListenerClass#errors | 21-partial | Error collection; aggregate codes only. | OWNED R1 |
| TCPListener.terminate() / https://developer.4d.com/docs/21/API/TCPListenerClass#terminate | 21-partial | Stops owned listener. | OWNED A2 |
| TCPConnection.closed / https://developer.4d.com/docs/21/API/TCPConnectionClass#closed | 21-partial | Boolean owned connection state. | OWNED R1 |
| TCPConnection.port / https://developer.4d.com/docs/21/API/TCPConnectionClass#port | 21-partial | Numeric port; suppress address. | OWNED R1 |
| TCPConnection.errors / https://developer.4d.com/docs/21/API/TCPConnectionClass#errors | 21-partial | Error collection; codes/count only. | OWNED R1 |
| TCPConnection.shutdown() / https://developer.4d.com/docs/21/API/TCPConnectionClass#shutdown | 21-partial | Shuts down owned connection. | OWNED A2 |

Filesystem create/delete/move/rename/write/read-content, SystemWorker commandLine/currentDirectory/response/responseError/postMessage, HTTP headers/URL/body/response, TCP send/address, UDP/WebSocket payload/event APIs and arbitrary constructors are excluded from dashboard information/admin surface. Object-owned status may be added only when that transport already belongs to the integration, not by opening new connections or subprocesses to probe.

## Coverage accounting and explicit exclusions

Relevant families accounted for: application/version/mode; system/OS/hardware/volumes; licenses; memory/cache/engine history; process activity and control; desktop/web/REST sessions; record/datastore/semaphore locking; transactions; schema/tables/fields/relations/indexes; file/storage metadata; backup/restore/journal; verification/compaction; logging/query diagnostics; app configuration/parameters; SQL service/client; web/REST/SOAP services; inbound/outbound TLS; users/groups/plugin access; data encryption; owned subprocess/HTTP/TCP integration health.

Excluded classic groups: UI/windows/menus/forms/list boxes/form events/user-interface process visibility; pictures/graphs/SVG/drag/pasteboard; printing/Quick Report/styled text/Write Pro/View Pro; strings/math/Boolean/date conversion/arrays/collections/JSON/XML/BLOB/resource manipulation; mail/LDAP/serial communications as private transport; generic language/compiler/method/design-object introspection except selected diagnostics; queries/selection/sets/records CRUD/relations traversal except aggregate count/schema/context flags. Table/field title setters, generic relation setters and arbitrary environment-variable reads/writes are not a first-release operational capability. UI administration/settings/runtime/security-center launch commands are excluded rather than misrepresented as headless admin APIs.

Excluded OOP groups: collection/vector/formula/class-store/method/function generic programming; Email/mail attachment/transporters; Blob/CryptoKey payload operations; WebForm/WebFormItem and UI; ZIP archive payload manipulation; application `cs.*` business members; entity/selection private data; Signal/QuotaManager generic methods and later-only quota features; network event/response objects except bounded owned-health metadata. The 51-class corpus cannot be used as a 21-LTS supported-class list.

This inventory is comprehensive across the defined operational families but is **not exhaustively verified per overload/selector**. `21-partial`/unknown entries need completion before implementation. No safe generic SQL-server running-state API, universal all-process transaction inventory, universal lock-owner release, all-OS-process/socket inventory, or LTS equivalent to the later index-description API was established; do not invent these from keyword matches or UI labels.

## Recommended implementation order and acceptance gates

1. **First PR: low-risk information gap, no actions.** Add a provenance-aware collector returning allowlisted `DataStore.getInfo()` type/networked scalars plus `DataClass.getInfo()` exposure/table metadata summarized as counts. Cache static schema summaries; no entities, arbitrary dataclass queries, `getIndexes`, `.quotas`, key/password/identity/path/log contents. Include `{capability,status,sourceScope,observedAt,value,unit}` and explicit unsupported/unavailable/error status, not zero or empty-success substitution. Standalone 21 LTS validates local behavior; actual Server/client deployment is still an unmet separate acceptance gate.
2. **Operational read-only PRs.** Cooperative BACKUP INFO last/next/status/duration metadata; current datastore encryption/admin-protection/write-lock flags where local eligibility is confirmed; bounded table/field/indexed/missing-table counts; separate configured-vs-effective web runtime metadata; allowlisted configuration/library versions; owned Go CLI process health. Review License info's reload side effect rather than classifying it as read-only. Collect process/session/lock aggregates on Server, not client. Size/time budgets, single-flight, last-good timestamps and sampling cost measurements required.
3. **Action safety substrate before ANY action.** Closed action-ID/parameter allowlists; real operator authentication plus per-action authorization; default deny; host/database/session target binding; expiring confirmations for consequential actions; request/correlation IDs; replay/idempotency rules; bounded queue and execution time; redacted audit of actor/action/target/start/outcome; preconditions and postconditions; no arbitrary command, SQL, method, formula, path, PID or session-token execution. Distinguish accepted asynchronous operation from completed postcondition. Never automatic retry for non-idempotent actions.
4. **Bounded low-risk maintenance, only after contracts/tests.** Prefer manually refreshed metadata and integration-owned diagnostic jobs/logging with capped duration/size and guaranteed cleanup. An owned subprocess/request cancellation can be bounded if ownership and recovery are verified. A fixed-template, one-target operator notification can precede server controls. ORDA cache clearing is only a candidate after exact client/cache scope and traffic consequences are tested; it is not universally low risk. Do not use FLUSH CACHE/free-all or tuning as ordinary maintenance.
5. **Higher-risk actions last, separate opt-in PRs.** Cache/config/security changes, backup initiation, connection admission, client disconnect/process abort, SQL/web stop/start, project reload/restart/quit need real Server+client fixtures, operator confirmation, async postcondition and recovery access independent of the dashboard transport. Never abort internal/system processes or disconnect via stale/recycled local identifiers.
6. **No general dashboard surface for destructive/offline work.** Restore/replay/compaction/encryption/key rotation/schema/import/index changes/truncate/data-file switch/user configuration import remain catalog-only until separately authorized requirements and disposable backup/restore validation exist.

For the coordinator's requested commit/merge sequence, treat each accepted increment as its own implementation PR in miyako/dashboard; this research session does not implement, commit or merge.

## Required validation matrix and remaining gaps

- **Not performed:** any 4D runtime execution, actual 21 LTS compile, standalone metric check, real Server/client/web/REST deployment, Windows counter/SSO behavior, private record/credential inspection, mutation or recovery test. Beta compiler evidence only establishes that corpus's syntactic controls.
- Minimum deployments: 21 LTS standalone; 21 LTS Server + remote client; real web/scalable-session/REST setup; host and hosted-component web servers; Windows for Windows-only counters/SSO/VSS; denied versus authorized operator roles. Do not waive missing Server.
- Verify scope: client Application info/System info must remain client-local; engine measures/cache/locked-records collector runs Server-side; License usage returns Null outside Server; License info can return Null without local license and can reload rights.
- Verify shape and units: Process info cpuUsage fraction vs Application info percent; cpuTime/uptime seconds; BACKUP INFO duration milliseconds; byte counts vs byte rates; date/time vs ISO timestamps; missing history -1 vs legitimate zero; configured option values versus runtime web values; legacy versus scalable session limits; selector GET/SET read/write units independently.
- Verify compatibility: no Session.quotas (21 R4), WebServer.quotas/start quota settings (21 R5), DataClass.getIndexes (21 R5), Session.info.unreachableSince (21 R4) in LTS output/contracts. Confirm exact command/member overloads on actual 21 LTS; Session info Integer-vs-UUID documentation is a specific unresolved signature issue.
- Verify privacy: fixture native objects containing sentinel IPs, paths, emails, license keys/numbers, OTP/token/session IDs, record IDs/query literals and session storage; assert none cross CLI/HTTP/log/audit boundaries. No raw-object serialization.
- Verify costs: increasing process/session/table/cache counts; measure collector duration/output bytes, bound detail and histories; no invented cadence guarantees. Independent clients must not multiply polling.
- Verify errors: invalid identifier, no local license, unsupported execution location, permission denial/password-system contention, service stopped, timeout and malformed/native-null results have distinct visible status and redacted error codes.
- Verify actions later: stale target/replay/unauthorized/wrong-host requests rejected; confirmation cancellation; concurrency/races; operation accepted vs completed; own transport loss; same-process nested datastore-lock cleanup; backup/VSS locks not released; recoverability and audit durability.

The most useful immediate delta is therefore a small version-21 metadata collector with explicit provenance and redaction, not additional mutation buttons or a claim that beta validation proves Server runtime behavior.
