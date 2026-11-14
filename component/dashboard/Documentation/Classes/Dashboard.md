# Dashboard

`cs.Dashboard.Dashboard` is the public facade for the CLI-backed, read-only
dashboard. Requires **4D 21 LTS or later**. It does not use 4D's web server.

`new(target : Text)` selects `macOS-universal` or explicit `Windows-x64`.
The bundled `dashboard` executable is resolved from component Resources only.

`start(options : Object; event : Object) : Object` asynchronously launches one
monitor per 4D instance. `event` is optional, with an optional `onStatus` Formula
or function: `onStatus(status : Object; monitor : cs.Dashboard.Dashboard)`.
It is invoked with `This` bound to the listener. Status snapshots contain
`kind,status,url,error,samples,epoch,port,finished`; kinds are `starting`,
`running`, `sample`, `failed`, `stopped`. URL contains a private authentication
token: do not log it. `running` follows real CLI readiness and registration
of the same worker at its real listening port through `cs.workers.worker`.
No fake/fixed registry port replaces OS-assigned port zero.
The running event includes `portCheck:{availability,listening}` from `tcp`;
query failure reports `availability:"error",reason`, not a free/occupied guess.

Native transport lives on `.workers`. Custom callbacks and native collection
run on the explicitly cooperative `Dashboard.callbacks.<epoch>` worker.
Ordinary objects are copied across processes; use shared listener state to
communicate with the original host owner, or explicit host dispatch for UI.
The callback's monitor is generation-bound and supports stop/restart reentrancy.
Exceptions are contained in `callbackError`; an existing transport error is
not overwritten. Callbacks must return promptly.

Returns shared `{status,url,error,samples,epoch,port,finished,callbackError,...}`
for compatibility; polling is optional, not the required callback interface.
Options: `listen` (IP:port), `allowLAN` (Boolean), `tls-cert`, `tls-key`
(absolute paths). Default authenticated `127.0.0.1:0`; LAN requires explicit
opt-in and valid TLS. Unknown/invalid options fail explicitly.

`stop()` queues graceful shutdown, closes stdin, then uses a finite 3.5-second
grace period and forced fallback if needed. Registration drainage precedes
replacement after force. A ten-second startup watchdog bounds pending ownership.
Transport, protocol and collection failures use the same finite stop watchdog;
delayed finalization prunes only the currently owned generation, never a replacement.
Terminal cleanup clears the private URL and prunes callback/collector/watchdog
workers and queued calls, not the shared `.workers` process. Unexpected exit
preserves stderr, emits `failed`, and permits restart after cleanup.
Repeated start does not replace the facade's active owned handle; stale handles
cannot stop a replacement. No host process-variable handle, unsafe PID map,
permanent host error handler or caller-blocking sampling loop is required.

`terminate() : Boolean` ends the instance's active dashboard whichever facade
started it, so shutdown code needs no stored handle; the target is not used.
It runs the same graceful stop and forced fallback as `stop()`, then waits up to
20 seconds until the dashboard is released, and returns `True` when nothing is
running (including when nothing was). It blocks the caller; call it from your
own process, such as `On Exit`, not from `.workers` (which returns `False`).

```4d
var $monitor : cs.Dashboard.Dashboard
$monitor:=cs.Dashboard.Dashboard.new()
$monitor.terminate()
```

**Deployment:** install `workers` 20.0.23 and `tcp` 20.0.14 as separate host
components alongside dashboard when using `Components/`. Dependency Manager
resolves the pinned declarations; the manual folder path ignores nested
declarations. Helpers are not bundled in Resources or the dashboard ZIP.
The exact archive hashes/revisions are in root `support-components.json`.

`collect() : Object` synchronously returns `{ok:true,value:{metrics,processes,
sessions}}` without starting HTTP. Its collectors run on the calling instance.
Use persistent monitoring to cache static OS/license fields; a one-off collect
constructs a fresh collector. Every metric reports availability, not invented
zero values. License info's documented rights reload occurs once per collector.
Only allowlisted scalar fields are returned.
Static datastore metadata uses the host's main `ds`, not the component's matrix
schema or a separately opened remote datastore. `DataStore.getInfo()` supplies
type/networked; `DataClass.getInfo().exposed` supplies mapped/exposed/unexposed
dataclass counts. At most 512 dataclasses are inspected once per collector.
Any enumeration failure/overflow invalidates the counts, with no partial totals.
Null datastore is unsupported. Counts exclude tables without a single primary
key and say nothing about records, indexes or effective REST permissions.
No names, primary keys, table numbers, paths, IDs or connection details are exported.
Restart the monitor after schema changes; one-off `collect()` reads fresh metadata.
Backup descriptors currently report unsupported even for an eligible local main
datastore: `BACKUP INFO` normally runs in component context and its host data-file
target has not been established. A local `ds` check is not proof of backup scope.
Remote/client and dataless hosts are also unsupported. Eligibility outcomes are
cached at least 60 seconds, including errors; `backup.observedAt` marks the check
in UTC. No unverified component result is presented as host history.
The cooperative read/normalization contract (fixture-tested only for positive
metadata) labels last/next dates as host-local wall times; the separately
validated begin timestamp is UTC. Duration is integer milliseconds; status is
an uninterpreted integer code, not a success flag. Both require recorded backup
evidence before zero or any other number is available. No history/schedule is
unknown, not zero/disabled; command failures and malformed data remain errors.
No raw status text, filenames, archive paths, records or identities are returned.
These descriptors use `kind:"static"` so repeated cached numbers never form rate
graphs. No backup/restore, arbitrary host-method bridge or configuration action is implemented.
`License usage` is sampled only on 4D Server, yielding total/per-product
retained-record gauges. Other contexts report unsupported. Session fields,
tokens/callers and historical retention-time balances are not exported.

`version() : Object` runs the finite CLI version command and decodes
`{"protocol":1,"version":"0.1.4"}`.

`inspect(text : Text) : Object` is a finite transport/quoting probe, returning
`{ok:true,stdout,stderr,exitCode:0,value:{protocol:1,text}}` for nonempty UTF-8
text. It is not a measurement. Empty input fails with exit 2. `_decode` checks
JSON object/type/protocol and keeps distinct stdout/stderr/status on failure.

Protocol/model/security/measurement scopes and examples are in the root
[README](../../../../README.md). `_DashboardCollector` owns normalization;
`_DashboardAgent` owns long-lived callbacks; `_CLI` and `_Process` remain generic.
Underscore classes are internal by convention, not access control.

The browser defaults to rolling time-series graphs, with separate static
information and database tabs. Process/session views include current snapshots
and bounded state/CPU tracking across the last 60 samples. Database graphs can
show cumulative totals or elapsed-time rates; missing samples and counter
resets create gaps. No change to the 4D methods or input protocol is required.
Uptime is an updating information readout, not a graph. License usage appears
in live tracking with at most 64 product identities retained per monitor.
License records have integer axes/step traces. Network rates share one
overlapping chart, as do cache used/capacity values; they are not summed.
Database I/O combines cache reads, cache misses and disk reads above a centered
time axis, with disk writes below it on an equal scale. Bytes and operation
counts stay separate. The read-side traces overlap without being summed;
individual colors/patterns and readouts distinguish their related measurements.
Readouts/tooltips show positive magnitudes; the normalized counters are unchanged.
