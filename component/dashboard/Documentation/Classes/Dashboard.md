# Dashboard

`cs.Dashboard.Dashboard` is the public facade for the CLI-backed, read-only
dashboard. Requires **4D 21 LTS or later**. It does not use 4D's web server.

`new(target : Text)` selects `macOS-universal` or explicit `Windows-x64`.
The bundled `dashboard` executable is resolved from component Resources only.

`start(options : Object) : Object` asynchronously launches one monitor per
4D instance in the `Dashboard.monitor` worker. Returns shared state
`{status,url,error,samples}`; status is `starting`, `running`, `failed` or
`stopped`. Read it from your application event loop. URL is available only
after readiness and includes a private authentication token: do not log it.
Options: `listen` (IP:port), `allowLAN` (Boolean), `tls-cert`, `tls-key`
(absolute paths). Default authenticated `127.0.0.1:0`; LAN requires explicit
opt-in and valid TLS. Unknown/invalid options fail explicitly.

`stop()` queues a graceful shutdown on the owning worker. It closes stdin,
waits up to two seconds, terminates a stuck child, clears state and kills the
worker with pending calls. Call from host shutdown. Unexpected termination
sets `failed`; explicitly stop before restarting. No global process map,
permanent host error handler or caller-blocking sampling loop is installed.

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
`{"protocol":1,"version":"0.1.0"}`.

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
