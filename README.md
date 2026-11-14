# dashboard

A **CLI-backed 4D component for 4D 21 LTS and later**. Each participating
4D client, standalone application or server launches its own bundled Go
executable. That executable serves the dashboard; **4D's web server is not
started or used**.

The first version is read-only: measurements, local process/session summaries,
refresh, and light/dark/system appearance. There are no administrative commands.
The researched [capability inventory and ordered roadmap](docs/dashboard-capabilities.md)
separates 21 LTS observations from later APIs and future, separately gated administration.
The mobile-aware interface uses system fonts, semantic HTML, keyboard-accessible
controls, high-contrast themes and incremental SSE updates without page reloads.
No CDN, JavaScript package manager or external runtime is needed.

**Live graphs** is the default view: scrolling stock/seismic-style traces with
time and value axes, actual sample dots and a rolling two-minute window.
Static metadata lives in **Instance information**; **Database** has its own
graphs and a rate-per-second / cumulative-total selector. Rates use elapsed
sample time, not an assumed frequency; resets, unavailable data and pauses over
15 seconds break the trace instead of inventing zero or interpolation.
The latest scalar is secondary to the graph. Changing tabs never stops collection.
Uptime remains an updating readout in **Instance information**, not a graph.
Live license-usage graphs count retained records returned by **4D Server**,
in total and by product; client, standalone and tool4d contexts show unsupported.
Record counts use whole-number axes and step traces, not fractional licenses.
The protocol rejects fractional/negative/unsafe record counts.
Network inbound/outbound rates share one overlapping chart; cache used/capacity
share another. Both use a common scale, separate colored/dashed traces and
individual readouts, not a misleading sum of capacity and usage.
Database cache reads, cache misses and disk reads overlay above a centered
horizontal time axis, with disk writes below it and equal scales on both sides.
The three read-side measures are related, not disjoint: they are **not summed**
or additively stacked. Each has its own color, line pattern and readout.
Bytes and operation counts have separate combined graphs. Rate/total switching,
missing-data gaps and counter resets are preserved; negative positioning is
presentation only, and readouts/tooltips retain positive I/O magnitudes.

**Processes & sessions** provides **Snapshot** tables and **Tracking** views:
counts over time, summed visible process CPU, per-process CPU, and per-identity
state/presence timelines, including recently disappeared identities. Missing
CPU is not zero; summed CPU is unavailable if any visible process lacks CPU.
An identity absent from a capped enumeration is not proof of termination.
Tool4d's unsupported process/session enumeration remains explicitly unavailable.

## Use from 4D

Install `dashboard.4dbase` in the host's `Components/` folder, or add the
`miyako/dashboard` GitHub dependency when an accepted release is available.
This revision also requires separately installed **workers 20.0.23** and
**tcp 20.0.14** components. Dependency Manager resolves the declared dependencies;
manual `Components/` installation must include all three `.4dbase` packages.
4D ignores nested dependency declarations for that manual installation path.
These are components, not native 4D plug-ins or private Resources backends.
The component, project, catalog and ZIP names are exactly `dashboard`.
The independently chosen namespace is `Dashboard`; ensure it does not conflict
with another component installed in your host.

For an accepted published asset, a host dependency entry is:

```json
{"version":2100,"dependencies":{"dashboard":{"github":"miyako/dashboard","tag": "0.1.0"}}}
```

New component tags are **prefix-free** SemVer (`0.1.0`, never `v0.1.0`).
This is not [Follow 4D version](https://blog.4d.com/follow-4d-version-a-smarter-way-to-manage-your-dependencies/):
that separate convention uses host-aligned tags such as `20.2.3` and `20R3.2`.
Do not select Follow 4D for this component's ordinary SemVer releases.

```4d
#DECLARE($params : Object)

If (Count parameters=0)
    
    CALL WORKER(1; Current method name; {\
    listen: "127.0.0.1:8443"; \
    allowLAN: True})
    
Else
    
    var $monitor : cs.Dashboard.Dashboard
    var $event : Object
    var $target : Text
    $target:="macOS-universal"
    If (Is Windows)
        $target:="Windows-x64"
    End if
    $monitor:=cs.Dashboard.Dashboard.new($target)
    $event:=New object("onStatus"; Formula(On_dashboard_status($1; $2)))
    $monitor.start($params; $event)
    
End if
```

Define the host's `On_dashboard_status` method:

```4d
#DECLARE($status : Object; $monitor : cs.Dashboard.Dashboard)
Case of
    : ($status.kind="starting")
        // $status.url is not usable yet.
    : ($status.kind="running")
        // $status.url is now usable. Do not log its private token.
        OPEN URL($status.url; *)
    : ($status.kind="sample")
        // Measurements have been sent; $status.samples has increased.
    : ($status.kind="failed")
        // Retain/report $status.error without disclosing the private URL.
    : ($status.kind="stopped")
        // The owned CLI has exited and its registration has been removed.
End case
```

`start(options; event)` returns immediately. The callback receives immutable
notification snapshots with `kind`, `status`, `url`, `error`, `samples`, `epoch`,
`port` and `finished`. Kinds are `starting`, `running`, `sample`, `failed` and
`stopped`. `running` requires the CLI's real readiness message **and** successful
registration of that same SystemWorker in `cs.workers.worker`. The default
remains authenticated `127.0.0.1:0`: the OS chooses the port; no fixed/fake
registry port or check-then-bind reservation is used. TCP observation appears
as `portCheck` on the running event, with explicit availability and listening
status; it does not establish health or expose process inventory.

The CLI/SystemWorker stays on `.workers`. Collection and custom host callbacks
run on the deliberately **cooperative** `Dashboard.callbacks.<epoch>` worker,
not on the UI process. `This` is the listener; ordinary listener/controller
objects are copied across workers. Use shared objects/collections for results
that must reach the original host owner, or deliberately dispatch UI work to
your own host worker. Do not assume a copied listener mutates a form object.
The callback's `$monitor` owns that specific generation and may call `stop()`
or restart after a terminal notification. Stale handles cannot stop a replacement.
Callback exceptions are contained and recorded separately in `callbackError`,
with the primary CLI error preserved. A callback must return promptly; do not
block collection, busy-wait, or manipulate UI from this background context.

When running, open `$status.url` in your browser. This URL contains a
private, randomly generated access token in its fragment. Treat it as a
password; do not log it or include it in support reports. The page exchanges it
for an HttpOnly, SameSite=Strict session cookie and removes it from the address
bar. The token/session expires when the CLI stops. The component never starts
the browser itself; the example callback above does it with `OPEN URL`, which
returns immediately.

```4d
// Call during your host's shutdown handling, and whenever monitoring ends.
$monitor.stop()
```

To shut down from code that does not hold the facade, use a fresh one.
`terminate()` stops whichever dashboard is active in this instance and waits
until it is released, so the host's `On Exit` database method can be:

```4d
var $monitor : cs.Dashboard.Dashboard
$monitor:=cs.Dashboard.Dashboard.new()
$monitor.terminate()
```

There is one active monitor per application instance. Duplicate starts fail
explicitly. `stop()` requests stdin EOF, allows a finite graceful shutdown, then forcibly
terminates a stuck child and drains its registration before allowing replacement.
The callback/collector, startup watchdog and stop worker are pruned; the shared
`.workers` support process is not killed because other components may use it.
An unexpected exit retains meaningful stderr and clears the connection URL.
Terminal notification follows cleanup; restarting needs no manual process-variable
reset. Keep the facade in your application-owned controller for shutdown, or
use the generation-bound facade passed to your callback.

**Migration:** `start(options)` still returns shared `{status,url,error,samples,...}`
state for existing callers, but polling it is no longer the only interface.
It now includes `finished`, `port`, `epoch` and separate callback diagnostics.
Repeated start on the same facade rejects without replacing its owned handle.
`stop()` remains asynchronous and the private URL is cleared on every terminal
transition. Internal `Dashboard.monitor`/`Dashboard_Agent` variables are not an API.

For a one-off normalized measurement without starting HTTP:

```4d
var $sample : Object
$sample:=$monitor.collect()
// Check $sample.ok before using $sample.value.metrics / processes / sessions.
```

### Browser exposure

The default is `127.0.0.1` with an OS-assigned port and mandatory authentication.
For explicitly enabled LAN access:

```4d
$monitor.start(New object(\
    "listen"; "192.168.1.20:8443"; \
    "allowLAN"; True; \
    "tls-cert"; "/absolute/path/server-cert.pem"; \
    "tls-key"; "/absolute/path/server-key.pem"); $event)
```

Use your machine's actual interface IP and a trusted certificate with that IP
in its subject alternative names. Non-loopback binding requires **both**
`allowLAN:true` and TLS. Wildcard binds and hostnames are rejected. There is no
unauthenticated mode, arbitrary shell execution or administrative action API.
Exact Host and Origin checks, same-origin POSTs, bounded bodies and a restrictive
Content Security Policy protect the browser interface. A token grants access
to all the allowlisted measurements for that instance; it is not a multi-user
authorization system. Do not expose it directly to the public internet.

## What measurements mean

### Synthetic database preview

To exercise the **Database** graphs without touching application data:

```sh
python3 scripts/preview_crud.py --root . \
  --tool4d .tools/tool4d.app/Contents/MacOS/tool4d \
  --component build/release-test/dashboard.4dbase --seconds 120
```

Use an already unpacked accepted component as above, or omit `--component`
to use the current source component with its already-built CLI resources.
The runner copies everything into a unique `build/crud-preview-...` directory
and creates a **fresh** `Data/CrudSample.4DD`. It never opens existing user data.
The sample project is `samples/crud/Project/CrudSample.4DProject`, with a
single indexed `CrudRecords` table, an auto-increment primary key and no journal.
Schema/project/ORDA guidance comes from
[`miyako/skills` at e6b492f](https://github.com/miyako/skills/tree/e6b492fcb81e5e1a7f7db723594b420e63bf6eb9/4d-skills/skills).

Every 16 seconds the workload creates 128 records with 8 KiB text payloads,
reads them through an indexed query, updates and rereads them by primary key,
then deletes them and verifies their absence. Save/drop status and exact
payload/count invariants are checked. Idle phases produce quiet intervals.
The table stays at most 128 records; normal completion leaves it empty.
**Testing only:** explicit `FLUSH CACHE` and `FLUSH CACHE(*)` force writes and
cache eviction to exercise disk-read counters. Never copy these flushes or the
workload into a production database; they deliberately distort performance.
The dashboard component and browser remain read-only.

The runner reports the isolated directory and readiness without printing the
access token. Its private `preview-status.json` contains the browser bootstrap
URL, current phase, operation counts and real `Database measures`.
Create the directory's `stop` file to finish the current CRUD cycle and stop.
`--seconds` accepts 30..43200; the default is a two-minute finite check.
`verification.json` requires successful CRUD round-trips, an empty final table,
clean CLI shutdown and positive observed disk/cache byte and access-counter
movement. Missing/reset counters fail rather than becoming zero.
These are synthetic local tool4d measurements, not a production benchmark or
4D Server/remote-client acceptance.

Collectors execute **where you start the component**. A client monitor is not a
server monitor. Run a separate monitor on 4D Server to collect server metrics;
this version neither aggregates instances nor executes remote administration.

| Source (4D 21 documentation) | Collected subset / scope |
| --- | --- |
| [Application info](https://developer.4d.com/docs/21/commands/application-info) | Local 4D CPU/uptime and machine network rates; Windows counters warm up before display |
| [Application type](https://developer.4d.com/docs/21/commands/application-type), [Application version](https://developer.4d.com/docs/21/commands/application-version), [Version type](https://developer.4d.com/docs/21/commands/version-type) | Static role, encoded version and version-type bitfield (not a Boolean) |
| [System info](https://developer.4d.com/docs/21/commands/system-info) | Static OS, CPU core count, physical memory in KiB |
| [Cache info](https://developer.4d.com/docs/21/commands/cache-info) | Cache bytes across host and loaded components (`dbFilter:"All"`); unsupported on remote clients |
| [Database measures](https://developer.4d.com/docs/21/commands/database-measures) | Eight top-level byte/access cumulative counters, no table/index names or native history; local/server only |
| [Process activity](https://developer.4d.com/docs/21/commands/process-activity), [Process info](https://developer.4d.com/docs/21/commands/process-info) | Local visible processes, CPU fraction, numeric type/state and opaque identity; activity entries retain internal processes unavailable through Process info |
| [Session info](https://developer.4d.com/docs/21/commands/session-info) | Opaque server session identity, type and state; enumeration requires the server's Process activity sessions list |
| [License info](https://developer.4d.com/docs/21/commands/license-info) | Product name only, once at collector construction; the command itself reloads license rights from disk. Null or command failure stays unavailable |
| [License usage](https://developer.4d.com/docs/21/commands/license-usage) | 4D Server only: total and per-product counts of the currently returned retained-license records, sampled every refresh |
| [Is compiled mode](https://developer.4d.com/docs/21/commands/is-compiled-mode) | Host mode (`*`), independently of the component's mode |
| [Is data file locked](https://developer.4d.com/docs/21/commands/is-data-file-locked) | Write protection, **not** record locks |
| [Is macOS](https://developer.4d.com/docs/21/commands/is-macos), [Is Windows](https://developer.4d.com/docs/21/commands/is-windows) | Collecting platform |
| [DataStore.getInfo()](https://developer.4d.com/docs/21/API/DataStoreClass#getinfo), [DataClass.getInfo()](https://developer.4d.com/docs/21/API/DataClassClass#getinfo) | Cached host main-datastore type/networked scalars and mapped/exposed/unexposed dataclass counts; no entities or schema names |
| [BACKUP INFO](https://developer.4d.com/docs/21/commands/backup-info) | Cooperative normalization contract for last/next wall times, uninterpreted status code, milliseconds duration and UTC begin timestamp; host-target scope remains unverified, so deployed host metrics are unsupported |

Every measurement has explicit `available`, `missing`, `unsupported` or `error`
availability. **Missing is not zero.** Empty database counters do not imply
zero I/O. Tool4d does not implement every full-application command; its license
errors and absent process enumeration are reported rather than fabricated.
Static OS/license information is cached for each monitor lifetime; restart the
monitor to refresh it. CPU percentages retain 4D's OS-specific semantics.
Process CPU is a 0..1 fraction; database counters are totals, not rates.

Datastore metadata is also cached per collector, appearing in **Instance information**.
`datastore.type` is the native `"4D"` / `"4D Server"` enum, not the application role;
the main `ds` remains `"4D"` on a remote client while `networked` is true.
Only the host's main `ds` is inspected, never `Open datastore` connections.
`datastore.classes`, `.exposed` and `.unexposed` count ORDA-mapped dataclasses,
not all physical tables, attributes, indexes or records. Tables without a single
primary key are not mapped. REST exposure is a schema flag, not proof of effective
authorization or a running REST server. Enumeration stops before a 513th
`getInfo()` call; overflow or any inaccessible/invalid class invalidates all
three counts, without publishing partial totals. A genuinely empty mapped model
can report zero; an absent datastore reports unsupported, never zero.
Restart monitoring after schema changes. Dataclass names, primary-key names,
table numbers, connection details and local datastore IDs never leave the collector.

Backup descriptors appear in **Instance information**, not rate graphs.
**Host backup metadata currently reports unsupported even with a local datastore.**
The [component command-scope rule](https://developer.4d.com/docs/21/Extensions/develop-components#scope-of-language-commands)
normally executes commands in component context; `BACKUP INFO` documents no
host-target override. A local main `ds` with `type:"4D"` and `networked:false`
establishes datastore eligibility, **not** the command's data-file target.
Until positive host-target evidence exists, the monitor does not read or present
component-context results as host backup history. Remote clients and dataless
hosts also report unsupported. No server delegation, arbitrary host-method bridge,
backup/restore or settings changes occur. Eligibility outcomes, including
failures, are cached for at least 60 seconds; manual refresh does not bypass
the cache. `backup.observedAt` is the UTC time of that eligibility check,
**not** the time of the current stream sample.

The cooperative read/normalization contract uses the vendor's
`String(date; ISO date; time)` for `backup.lastAt` / `.nextAt`, explicitly
**host-local** wall time without a timezone suffix.
Null dates stay missing; a present date with zero Time is valid midnight.
`backup.beginUTC` accepts only the documented `yyyy-MM-ddTHH:mm:ss.SSSZ`
Timestamp format with a valid calendar date; it is never derived by appending
`Z` to local time. Calendar validation passes a full ISO date/time to
[`Date`](https://developer.4d.com/docs/21/commands/date): a bare `YYYY-MM-DD`
would instead use regional short-date parsing and reject valid values on
US-English hosts. `backup.duration` is integer **milliseconds**, not seconds.
A valid last date or begin timestamp establishes recorded-backup evidence before
duration (including zero) or `backup.statusCode` can be displayed. Neither
evidence nor any numeric status code proves a successful backup; the vendor
does not document code meanings here. Absent history, failures and invalid
outputs never become zero/success or a disabled schedule. Raw status text,
paths, filenames, archive names and record/identity data are never exported.

On the pinned 21.1 Apple Silicon tool4d, independent fresh-data source and
compiled fixtures call `BACKUP INFO` both directly in the host and from the
component. Both return empty last/next/begin dates, with uninterpreted numeric
outputs. **Matching empty histories do not establish the command's target.**
Deployed descriptors remain unsupported; the dataless fixture is unsupported
independently. Positive metadata is exercised only by normalization fixtures,
**not** an actual backup operation. Real positive host targeting/history,
scheduled backup, IDE/Server/remote-client and native Intel/Windows behavior
remain separate unobserved deployment boundaries.

The opt-in `scripts/test_backup_scope.py --tool4d PATH --component PATH` probe
stages a fresh synthetic host and creates **only its own** documented
[21 XML backup settings](https://doc.4d.com/4Dv21/4D/21/4D-XML-Keys-Backup.100-7678272.en.html).
It verifies native data/settings/log paths before making one data-only `BACKUP`
attempt; archive destination uses 4D's native `.platformPath` and automatic
restore/log integration/restart are disabled. It never opens existing data,
starts the dashboard or modifies shared applications/settings. On 21.1 tool4d,
the attempt stayed in `backup` until the **45-second timeout**, created no
archive and produced no backup-specific error diagnostic. The process was
stopped; this is **failed**, not passed target evidence. The
[tool4d CLI reference](https://developer.4d.com/docs/21/Admin/cli#disabled-4d-features)
also explicitly disables its backup scheduler. Positive host targeting therefore
remains blocked on a separately verified supported runtime, not inferred from
empty-history comparisons or lexical component context alone.

License usage sends only product IDs/names and derived record counts. It never
sends license tokens, reasons/callers, retention timestamps or session objects.
The command's `productUsedCount`, `productBalance` and
`globalProductUsedCount` describe values **at retention time**, not a fresh
census; they are not summed or presented as current capacity. Known products
remain at zero when absent from a successful complete enumeration, so releases
remain visible on their graphs. Errors/Null produce gaps, never zero.
At most 64 product identities are retained per monitor lifetime; exceeding
that limit reports an error without accepting partial counts.

Only allowlisted scalar fields leave 4D. User/account names, machine names,
process names, session usernames/IPs, license numbers/keys/email/company,
network interfaces, filesystem paths and table/index details are not sent.
Lists have a 512-entry cap with explicit truncation measurements. Process IDs
are unique within the instance epoch; session IDs are opaque and change with
sessions. Full snapshots replace both lists, deleting disappeared entries.

## Extending independently

`_DashboardCollector` is the 4D-only command/normalization layer;
`_DashboardAgent` owns the stream/lifecycle; the Go `protocol.go` model has no
4D or HTML dependency; `server.go` implements HTTP/auth/SSE; `web/app.js`
renders declarative metric descriptors and `web/style.css` controls appearance.
Add a metric in the collector without adding a server endpoint or editing the
renderer. Add a new widget type in presentation without changing collection.
Public API: [Dashboard](component/dashboard/Documentation/Classes/Dashboard.md).
Generic execution remains in [_CLI](component/dashboard/Documentation/Classes/_CLI.md)
and [_Process](component/dashboard/Documentation/Classes/_Process.md).

### Protocol 1

UTF-8 NDJSON, one JSON object per LF-terminated frame, at most 256 KiB/frame.
Diagnostics go to stderr **only**; stdout is reserved for typed messages.
4D's callback accumulates arbitrary output chunks until LF and rejects oversized
frames. Each producer serializes writes. A stdin protocol error is fatal, not
silently skipped.

CLI to 4D:

```json
{"protocol":1,"kind":"ready","url":"http://127.0.0.1:PORT/#token=PRIVATE","version":"0.1.0"}
{"protocol":1,"kind":"request","epoch":"INSTANCE-UUID","id":"64-lowercase-hex","action":"refresh"}
```

4D to CLI: `hello` first (`seq:1`), then `snapshot`, `update` or `result`.
All frames include `protocol:1`, a fixed `epoch`, exactly increasing safe-integer
`seq` and an RFC3339 `sampledAt` timestamp with a timezone. A new monitor creates
a new epoch; restart the CLI to reset the stream. Unknown fields/kinds, invalid
types, sequence gaps/replays and mismatched epochs fail explicitly.

```json
{"protocol":1,"kind":"hello","epoch":"instance-1","seq":1,"sampledAt":"2026-11-13T07:00:00Z","info":{"role":"standalone","platform":"macOS"}}
{"protocol":1,"kind":"snapshot","epoch":"instance-1","seq":2,"sampledAt":"2026-11-13T07:00:02Z","metrics":[{"id":"app.cpuUsage","label":"4D CPU","type":"number","unit":"%","kind":"gauge","availability":"available","value":12.5}],"processes":[],"sessions":[]}
{"protocol":1,"kind":"result","epoch":"instance-1","seq":3,"sampledAt":"2026-11-13T07:00:02Z","id":"request-id","ok":true}
```

`snapshot` replaces all metrics/entities; `update` upserts them by ID and
optionally removes IDs through
`delete:{"metrics":[],"processes":[],"sessions":[]}`.
Metric descriptors specify `type` (`number`, `text`, `boolean`), `unit`, `kind`
(`static`, `gauge`, `counter`) and availability; unavailable entries omit
`value` and include a nonempty `reason`. Process/session objects have `id`,
`type`, `state` and optional process `cpu`.

The normalized store allows 256 metrics, 512 processes and 512 sessions, and
60 timestamped history points per dynamic numeric metric (including explicit
null gaps) and 60 activity samples, each bounded to 512 process and 512 session
state/CPU entries. Activity enumeration is null when unavailable, distinct
from a known empty Object. Snapshot/update frames record samples; action-result
frames do not duplicate history. Histories survive browser reconnects but are
in-memory only and reset with the CLI. The identity selector shows at most
512 recent identities per kind, prioritizing the current snapshot.
At most 16 SSE viewers receive full
normalized state on connect/reconnect and subsequent updates; queued states
coalesce to the latest for slow consumers. Stream writes have finite deadlines.
HTTP POST `/api/refresh` emits a correlated read-only request; one request may
be outstanding, rate limited to one/second, with a ten-second timeout. There is
no automatic replay of browser actions; late results are consumed once through
a bounded 32-ID timeout registry. Sampling stops being fresh after 15 seconds;
the browser distinguishes stale, waiting and disconnected states.

### CLI

| Invocation | Result |
| --- | --- |
| `dashboard serve` | Authenticated loopback server; lifecycle tied to stdin |
| `dashboard --version` | `{"protocol":1,"version":"0.1.4"}` + LF |
| `dashboard inspect --text "literal"` | Protocol/argument probe: `{"protocol":1,"text":"literal"}` + LF |
| Invalid arguments/protocol | Exit 2; structured error diagnostics on stderr |

The finite `inspect` command is a quoting/transport probe, not a collector.
The real source and compiled host fixtures additionally start the service,
feed live collected measurements, receive refresh requests and stop it.

## Build and acceptance

Go standard library only, source minimum Go 1.23; CI pin remains 1.26.10.
`support-components.json` pins the separately deployed helper release archives,
source-tag revisions and SHA256 hashes. Acceptance downloads/verifies those
archives, explicitly loads their compiled packages in both host stages, and
passes their `.4DZ` files to the real compiler's `components` option. The helper
lock and exact loaded identities are bound in compiler/host/package evidence
and preserved in the isolated signing mirror. The dashboard ZIP does **not**
bundle the helpers. Their MIT licenses remain upstream; tcp's own `procs` runtime
and redistribution remain part of that separate published package, not this Go CLI.
Verified local integration is tool4d 21.1 on Apple Silicon; upstream 20.7 compiler
metadata alone is not evidence of other 21 LTS host/platform compatibility.
The build embeds HTML/CSS/JavaScript via `go:embed`; there is no separate frontend
dependency installation. macOS ships a universal executable; Windows ships x64.
Native Windows ARM64 is unsupported. Follow the actual 4D host OS requirements.
The free macOS ARM64 tool4d pin is **21.1 / archive build 100562**, fixed URL and
SHA256 in `package.json.tool`. Do not substitute `latest` in acceptance.
The original template's 20.7 compiler cannot validate the 21 LTS floor.

```sh
python3 -m unittest discover -s tests -v
python3 scripts/generate_icons.py --check
(cd cli && go test -race ./... && go vet ./... && node --check web/app.js && node --check web/charts.js)
node --test tests/test_charts.cjs
python3 scripts/ci_config.py download-tool4d --root .
python3 scripts/accept_local.py --root . --repository miyako/dashboard \
  --tool4d .tools/tool4d.app/Contents/MacOS/tool4d --cross
```

`--cross` here produces Go artifacts on macOS, **not** native foreign-platform
execution. Require the exact final ZIP's unpacked source-stripped component to
pass the real compiled-host contract. Preserve `dist/dashboard.zip` alongside
`dist/dashboard.acceptance.json` outside disposable worktrees. Local acceptance
remains **partial / release_ready:false**: native Intel/Windows 4D, actual
client/server sessions, normal IDE/Server loading and Dependency Manager
installation require separate execution. Tool4d evidence is not those checks.
The inherited fresh-template multi-language initializer/version-fixture tests
are skipped after initialization, as their starter sources are intentionally
removed; destination-specific version surfaces are checked separately.

CI is nonpublishing. **Bump version** updates synchronized source metadata on
the selected branch; **Build** publishes only after separate authorization,
main-only immutable-SHA acceptance and the existing provenance/signing gates.
Use **Actions → Bump version → Run workflow**, select the source branch and
patch/minor/major, then separately run **Actions → Build → Run workflow** on
main after the version and implementation are merged. Build does not bump the
version or follow a newer main commit; it builds/tests all three native CLI
targets and accepts the compiled component at the exact dispatch SHA.
`FOURD_ENABLED=true` must be configured as an Actions variable for Build's
required hosted component checks.

Build publishes `dashboard.zip` and `dashboard.acceptance.json`, plus standalone
`dashboard-cli-macos-universal.zip`, `dashboard-cli-windows-x64.zip` and
`dashboard-cli.json`. Extract the appropriate CLI archive to get `dashboard`
or `dashboard.exe`, the MIT license and bundled runtime notices; no 4D installation
is needed to run the CLI itself. A producer must still supply the
[stdin protocol](#protocol-1); the CLI does not collect 4D metrics by itself.
The CLI archives are derived from the exact accepted component ZIP, not rebuilt
or substituted after host acceptance. Their manifest records archive/binary
hashes, shared version, source revision and original component/evidence hashes.
All download bytes are checked before creating the new version tag and release.
CI and Bump version never publish these assets.

Signed Build additionally publishes the existing component DMG and signing
proof. Before signing, an isolated copy retains all compiler input metadata,
including `workflow-contract.json` when present, and must reproduce the accepted
unsigned ZIP byte-for-byte. Changed inputs still fail the original digest gate;
the signing helper never recompiles or rewrites the original compile marker.
The standalone macOS CLI retains the accepted binary's Developer ID
signature; its ZIP is not a stapled container. The component DMG remains the
notarized/stapled download. Windows Authenticode is not implemented.
No tag, release, signing secret or publication is required for local acceptance.
The inherited `workflow-contract.json` is checked with
`python3 scripts/workflow_contract.py --root .`; install its development-only
parser from `tooling/requirements-workflow.txt` if missing.
Optional signed-release credentials remain
[user-owned](AGENTS.md#user-owned-credential-setup-and-reuse):
only the user runs `scripts/set-release-secrets.sh`; setup does not authorize
publication or make signing mandatory.
See [AGENTS.md](AGENTS.md) for the full inherited packaging/release playbook.
The MIT license and bundled Go runtime notice are retained; tool4d is not bundled.
