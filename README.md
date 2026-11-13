# dashboard

A **CLI-backed 4D component for 4D 21 LTS and later**. Each participating
4D client, standalone application or server launches its own bundled Go
executable. That executable serves the dashboard; **4D's web server is not
started or used**.

The first version is read-only: measurements, local process/session summaries,
refresh, and light/dark/system appearance. There are no administrative commands.
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

**Processes & sessions** provides **Snapshot** tables and **Tracking** views:
counts over time, summed visible process CPU, per-process CPU, and per-identity
state/presence timelines, including recently disappeared identities. Missing
CPU is not zero; summed CPU is unavailable if any visible process lacks CPU.
An identity absent from a capped enumeration is not proof of termination.
Tool4d's unsupported process/session enumeration remains explicitly unavailable.

## Use from 4D

Install `dashboard.4dbase` in the host's `Components/` folder, or add the
`miyako/dashboard` GitHub dependency when an accepted release is available.
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
// Keep these in your application-owned controller, not transient local variables.
var DashboardMonitor : cs.Dashboard.Dashboard
var DashboardStatus : Object
var $target : Text
$target:="macOS-universal"
If (Is Windows)
    $target:="Windows-x64"
End if
DashboardMonitor:=cs.Dashboard.Dashboard.new($target)
DashboardStatus:=DashboardMonitor.start(New object)
```

`start()` returns immediately with a shared status object:
`{status:"starting",url:"",error:"",samples:0}`. A named `CALL WORKER` worker owns
the SystemWorker, collection and callbacks. No sampling loop monopolizes that
worker. The CLI asks for a sample every two seconds over stdout; the worker
collects and posts NDJSON to stdin. `status` becomes `running` only when the CLI
reports its listening URL. Observe the shared status from a form timer or your
application event loop; **do not busy-wait on the UI process**.

When running, open `DashboardStatus.url` in your browser. This URL contains a
private, randomly generated access token in its fragment. Treat it as a
password; do not log it or include it in support reports. The page exchanges it
for an HttpOnly, SameSite=Strict session cookie and removes it from the address
bar. The token/session expires when the CLI stops. The component never starts
the browser automatically.

```4d
// Call during your host's shutdown handling, and whenever monitoring ends.
DashboardMonitor.stop()
```

There is one active monitor per application instance. Duplicate starts fail
explicitly. `stop()` closes stdin, allows a finite graceful shutdown, terminates
a stuck child, clears owned state and kills the component worker/queued calls.
An unexpected exit sets `status:"failed"` and `error`; call `stop()` before
restarting. EOF on stdin also shuts the web server down. Do not retain orphaned
monitor processes across database shutdown.

For a one-off normalized measurement without starting HTTP:

```4d
var $sample : Object
$sample:=DashboardMonitor.collect()
// Check $sample.ok before using $sample.value.metrics / processes / sessions.
```

### Browser exposure

The default is `127.0.0.1` with an OS-assigned port and mandatory authentication.
For explicitly enabled LAN access:

```4d
DashboardStatus:=DashboardMonitor.start(New object(\
    "listen"; "192.168.1.20:8443"; \
    "allowLAN"; True; \
    "tls-cert"; "/absolute/path/server-cert.pem"; \
    "tls-key"; "/absolute/path/server-key.pem"))
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

Every measurement has explicit `available`, `missing`, `unsupported` or `error`
availability. **Missing is not zero.** Empty database counters do not imply
zero I/O. Tool4d does not implement every full-application command; its license
errors and absent process enumeration are reported rather than fabricated.
Static OS/license information is cached for each monitor lifetime; restart the
monitor to refresh it. CPU percentages retain 4D's OS-specific semantics.
Process CPU is a 0..1 fraction; database counters are totals, not rates.

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
| `dashboard --version` | `{"protocol":1,"version":"0.1.0"}` + LF |
| `dashboard inspect --text "literal"` | Protocol/argument probe: `{"protocol":1,"text":"literal"}` + LF |
| Invalid arguments/protocol | Exit 2; structured error diagnostics on stderr |

The finite `inspect` command is a quoting/transport probe, not a collector.
The real source and compiled host fixtures additionally start the service,
feed live collected measurements, receive refresh requests and stop it.

## Build and acceptance

Go standard library only, source minimum Go 1.23; CI pin remains 1.26.10.
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
