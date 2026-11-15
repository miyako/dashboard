# CLI restart strategy (#19, part 1)

Written before the implementation; it is the reference for `_DashboardAgent` and the host tests.

## Today

A CLI that exits unexpectedly fails the dashboard. Nothing restarts it, and the host has to call
`start()` again.

## How 4D reports an exit (measured on tool4d 21.1, `scripts/probe_native.py`)

| How the process ended | `exitCode` | `terminated` |
| --- | --- | --- |
| Normal exit | `0` | |
| CLI-detected error (the CLI always exits **2**, with a JSON error on stderr) | `2` | |
| Killed by a signal (`KILL`, `SEGV`, `TERM`) | **not a number** | `True` |
| `SystemWorker.terminate()` | not a number | `True` |

## Classification

| Situation | Restart? | Why |
| --- | --- | --- |
| We stopped it (`stop()`, host shutdown, `terminate()`, a callback stop) | No | Intentional |
| 4D found a protocol or validation problem (`fail()` is called first) | No | A bug on either side; a restart would loop |
| Ended before `ready` (startup: options, port in use, TLS, missing binary) | No | Configuration; reported to the host |
| CLI exit **2** while running | No | The CLI reported its own error (on stderr), for example a protocol violation, backpressure or a listener error |
| Signal death while running (`exitCode` not a number) | **Yes** | Crash or external kill |
| Exit **0** while running, without our stop | **Yes** | Unexpected end |
| Any other exit code while running | **Yes** | Unexpected end |
| **Unresponsive**: no frame from the CLI for the liveness limit while running | **Yes**, after a controlled stop | Hung |

**Liveness:** the CLI sends a `request` at least every 10 s (the slowest cadence) while 4D answers.
After **45 s** without any frame from the CLI, the agent stops it in a controlled way. It closes stdin,
then, as `stop()` already does, forces termination after 3.5 s. Then it restarts. Liveness is **not**
checked while an exclusive action runs, because the CLI deliberately pauses sampling then (A0).

## Budget and backoff

- At most **5 restarts in any 10 minutes**. The next unexpected exit fails the dashboard with
  `Dashboard CLI restart limit reached`, plus the last diagnostic.
- The delay before restart *n* within the window is `1 s × 2^(n−1)`, capped at 60 s: 1, 2, 4, 8, 16 s.
- Hosts may tune this with `start(New object("restart"; New object(...)))`:

  | Key | Range | Default |
  | --- | --- | --- |
  | `max` | 0–10; **0 disables restarts** (the old behavior) | 5 |
  | `windowSeconds` | 60–3600 | 600 |
  | `initialDelayMs` | 250–10000 | 1000 |
  | `livenessSeconds` | 15–300 | 45 |

  Any other key or an out-of-range value fails `start()`.

## What a restart means

- **A new CLI process:** new viewer and operator tokens, a new URL (and a new port unless `listen`
  fixes it), and empty in-memory history (M5). Browser sessions must reopen the new URL.
- **A new protocol epoch for each CLI run:** `<epoch>` for the first run, `<epoch>.r1`, `<epoch>.r2`
  and so on after. An executor result from an earlier run is audited as `orphaned` and never sent to
  the new CLI (A0 routing). The instance identity `state.epoch` does not change, so `stop()`,
  `terminate()` and the facade's handle keep working.
- **The host sees it:**
  - `onStatus` gets `kind:"restarting"` with `reason` (`crashed`, `exited` or `unresponsive`),
    `attempt` and `delayMs`.
  - Then `kind:"running"`, with the new `url` and `operatorUrl` and `restarts` (the total so far).
  - Shared state carries `status:"restarting"`, `restarts` and `lastRestartReason`. During the delay,
    `url` and `operatorUrl` are empty.
- **Old registration:** the old port's server registration is released before relaunch.
- **No duplicates:** at most one restart is pending; a `stop()` during the delay cancels it.

## Not in scope

Restarting 4D itself, persisting history across restarts, keeping tokens across restarts (a new
process must not inherit secrets), and restarting after host-requested shutdown.
