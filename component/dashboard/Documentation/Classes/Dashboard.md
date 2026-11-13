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
