# Administrative actions: design for the next phase

Status: **proposal for review**. Nothing here is implemented or enabled. This
builds on the operator pipeline from M3/M4 (`docs/operator-actions.md`) and keeps
every existing guarantee: off by default, closed catalog, single-use bound
confirmation, fail-closed audit and no automatic retry.

## 1. The bridge today

Two processes connected by two pipes. The 4D component owns the CLI's
lifetime: it starts it as a `4D.SystemWorker`, and when it closes the CLI's
stdin the CLI exits.

```
Browser ──HTTPS/HTTP──▶ Go CLI (cli/)                     4D component (component/dashboard)
                         │                                  │
                         │  stdout: NDJSON frames ────────▶ │ SystemWorker.onData   (worker ".workers")
                         │  stdin:  NDJSON frames ◀──────── │ SystemWorker.postMessage
                         │  stderr: diagnostics only        │
```

**CLI → 4D (stdout).** HTTP handlers and the scheduler never write to the
pipe directly. They call `service.emit(frame)`, which puts the frame on a
bounded queue (`out`, 64 frames) or fails at once when the queue is full
(`dispatch_failed`). A single goroutine in `main.go` takes frames off the
queue and JSON-encodes each as one LF-terminated line on stdout. One writer
means frames never interleave. Kinds: `ready`, `request` (refresh) and
`action`.

**4D receives.** `_DashboardAgent.onData` runs on the `.workers` worker, which
can run preemptively. It appends each chunk to a buffer, rejects a buffer over
256 KiB, splits on LF, `JSON Parse`s each line under a local error handler and
dispatches on `kind`. Validation is strict: an unknown kind, field, epoch or
type fails the instance.

**4D → CLI (stdin).** `_DashboardAgent.send` stamps `protocol`, `kind`,
`epoch`, an exactly increasing `seq` and `sampledAt`, then calls
`postMessage(JSON+LF)`. Because only `.workers` sends, frames stay in order.
The CLI reads stdin line by line (at most 256 KiB, UTF-8, strict decode) in
`service.read` → `apply`.

**How an action runs today (`operator.noop`, `monitor.*`):**

1. The browser posts to `request`; the CLI issues a confirmation.
2. The browser posts to `confirm`; the CLI emits `{kind:"action", id, action, args, actor}`.
3. `onData` calls `_DashboardOperator.begin`, which validates the frame and
   writes the `running` audit record. If that write fails, the action fails
   with `audit_unavailable` and nothing runs.
4. Still inside `onData`, `complete` executes the action and writes the final
   audit record.
5. `send("actionState")` reports `running`, then `completed` or `failed`.
6. The CLI applies the result (M4 controls only) and shows it in operator
   status.

**How a sample runs:** the Go ticker emits a `request`, and `onData` calls
`sample()`. That does a `CALL WORKER` to the cooperative worker
`Dashboard.callbacks.<epoch>`, which runs the collector, then waits up to 5 s on
a signal and replies with `snapshot` and `result`.

## 2. Is this bridge ready for administrative actions? Review

| # | Finding | Consequence for admin actions | Severity |
| --- | --- | --- | --- |
| R1 | Actions execute **inside `onData`** on `.workers` | A command that takes seconds blocks reading the CLI's stdout. The OS pipe fills, the CLI's queue fills, every `emit` fails, and refresh and further actions break. | Blocking |
| R2 | `.workers` is **preemptive**, and most administrative commands are not thread-safe | They can't run there at all, so a cooperative worker is required | Blocking |
| R3 | A sample that takes **over 5 s is fatal** (`fail("Dashboard collection timed out")`) | Any action that loads the data engine (flush, lock, backup) can kill the monitor through the sampler, not through the action | Blocking, and already a latent risk today |
| R4 | The action timeout is fixed at 30 s, after which the outcome is unknown | A backup or a big flush legitimately takes longer, and would always be reported as `outcome_unknown` | High |
| R5 | No progress, and no postcondition beyond the 4D "completed" | "Completed" can only mean the command returned, not that the effect happened | High |
| R6 | If the CLI dies mid-action, the 4D side keeps running with no owner | An action can finish with nobody to report to; a lock (e.g. `flushAndLock`) could stay held | High for stateful actions |
| R7 | The catalog is **written twice**, in Go and in 4D | The two can drift; today only tests catch it | Medium |
| R8 | One operator role, from one token | No per-action authority; the host can't express "only this user may start a backup" | Medium |
| R9 | Native commands can **crash 4D outright** (selectors 114/115 segfaulted tool4d in M2b) | No error handler protects against a crash | High; needs a probe gate |
| R10 | After a sampler timeout the agent holds no reference to itself on `.workers` (`Dashboard_Pending` is cleared once adopted) | A result coming back from another worker has no route to `send` | Implementation gap |
| R11 | Operator mode works over plain HTTP on loopback | Acceptable for no-ops; weak for consequential actions, which LAN plus TLS already protects | Medium |

The parts that hold up and should stay as they are: strict framing and
validation, one writer per direction, epoch and sequence binding,
single-use confirmations bound to actor, arguments, target and expiry, one
action in flight, fail-closed audit, `outcome_unknown` instead of guessing,
and no retries.

## 3. Refined design

### 3.1 A dedicated cooperative executor, with an asynchronous return path (fixes R1, R2, R10)

```
.workers (onData)                     Dashboard.admin.<epoch> (cooperative)          .workers
──────────────────                    ──────────────────────────────────────          ────────
validate + audit "running"
send actionState running
CALL WORKER(admin; "_DashboardAdmin";  ──▶ run closed command under local
           "run"; frame, deadline)         ON ERR CALL; capture native error codes
return immediately                         verify postcondition (read back)
(onData keeps serving refresh)             write final audit record
                                           CALL WORKER(".workers"; "_DashboardWorker";
                                                       "actionResult"; epoch, id, outcome) ──▶ look up the agent for this epoch
                                                                                              agent.send("actionState", final)
```

- `.workers` keeps an epoch-keyed reference to the live agent
  (`Dashboard_Agent`), so the result returns to the instance that dispatched it
  and never to a newer one. A result for a stale epoch is audited as
  `orphaned` and dropped.
- The executor is **cooperative** (`preemptive: incapable`), so it can call
  commands that aren't thread-safe. It runs one action at a time, in a FIFO of
  length 1, matching the CLI's single in-flight action.
- A native error is reduced to a **closed code**, e.g. `native_error_<code>`.
  Native message text, which can contain paths, never reaches the CLI.

### 3.2 Sampling must survive actions (fixes R3; compatibility in section 5)

- **A sample timeout stops being fatal.** `sample()` answers the refresh with
  `result {ok:false, error:"collector_busy"}` and keeps the instance alive.
  Only *N* consecutive timeouts (e.g. 6, about 30 s) or a transport failure end
  it. That is worth doing on its own, before any admin action.
- **Each catalog entry carries `exclusive: true|false`.** For an exclusive
  action, 4D includes `exclusive:true` in its `running` frame. The Go
  scheduler then **pauses** sampling, and the viewer state shows status
  `maintenance` ("Paused for a maintenance action"). Viewers see no action ID,
  actor or arguments, and the pause isn't mistaken for `stale`. Sampling
  resumes on the final state or at the deadline.

### 3.3 One catalog, with per-action metadata (fixes R4, R7)

A single checked-in `contracts/actions.json` becomes the source of truth.
Go's `go:embed` and 4D's resources load the same bytes, and a CI test fails if
either side's behavior diverges from it. Each entry:

| Field | Purpose |
| --- | --- |
| `id`, `tier` | Closed ID; tier A, B or C (section 4) |
| `args` | Closed schema: types, enums, ranges; canonical JSON |
| `scope` | `standalone`, `server` or `any` (`server` is refused elsewhere) |
| `deadlineMs` | Per action; replaces the fixed 30 s. Past it the outcome is `outcome_unknown`, never assumed failed |
| `exclusive` | Pauses sampling while the action runs |
| `progress` | Whether `running` frames may carry `{phase, percent}` (at most 1/s, bounded codes) |
| `verify` | The read-back that defines success (section 3.5) |
| `undo` | The paired action, if any (e.g. `datastore.unlock`), and an automatic expiry for held state |
| `approval` | `operator` (A) or `operator+host` (B, C) |
| `transport` | `any` (A) or `tls_or_loopback_only` (B, C) |

### 3.4 Authority: the host decides (fixes R8, R11)

The design invents no 4D role. For tier B and C actions, `start()` takes a
host callback:

```4d
$monitor.start(New object("operator"; New object("actions"; New collection("cache.flush"); \
    "authorize"; Formula(My_dashboard_authorize($1)))); $event)
```

- The component calls it on the executor before running anything, with
  `{action, args (canonical), actor (hashed), tier}`.
- Only `True` proceeds. Anything else, including an error or more than 5 s,
  fails with `host_denied` and is audited.
- This is where an application plugs in its own users, schedules ("never
  during business hours") or second approver.
- A tier B or C action listed without `authorize` fails `start()`.

### 3.5 Results mean effects, not returns (fixes R5)

- `completed` is reported only when the `verify` read-back confirms the
  intended state, e.g. `ds.isAdminProtected()` now matches the request.
- When the command returned but the read-back disagrees, the action reports
  `failed: postcondition_unmet` and gives no undo hint.
- Actions without an observable effect (`FLUSH CACHE`) are marked
  `verify: none` and report `completed` with `unverified: true`, so the UI never
  calls them confirmed.
- After a verified action, the collector cache that covers the affected metric
  is invalidated, so the next sample shows the new state instead of a 60 s old
  cached value.

### 3.6 Orphans and held state (fixes R6)

- Any action that leaves state held (a write freeze, a request log) must
  declare `undo` and a **maximum hold**. The executor arms a 4D-side timer
  (the executor's own `DELAY PROCESS` loop, never the CLI) that runs the undo
  when the hold expires, **or when its epoch ends**.
- Agent `finish()` runs the undo for any held state before the CLI closes. A
  crash of 4D itself releases in-memory locks anyway.

### 3.7 Native safety gate (fixes R9)

Before a command enters the catalog, it is called from a standalone probe
project, the way selectors 114/115 were found, on tool4d and on full 4D for
each supported platform. A crash removes it permanently, and the exclusion
list (with dates and builds) lives next to the catalog.

### 3.8 Frames (additions only; protocol 1 framing unchanged)

- 4D → CLI `actionState` gains optional `exclusive` (on `running`),
  `progress {phase, percent}` (on `running`), `unverified` (on `completed`) and
  `result` (a bounded object of at most 2 KiB, whose fields each catalog entry
  declares).
- The CLI rejects any optional field the catalog entry didn't declare.
- 4D → CLI also gains `actionOrphaned {id}`, sent when a previous epoch's action
  finishes after its CLI is gone. It is audited only and never applied.
- `cancel` is not added generally. An action may declare it only when 4D has a
  native way to stop it.

## 4. Candidate administrative tasks

The effects of each command below are to be confirmed against the 4D 21 docs
and a probe before any contract is written. A **verify** entry names the
existing metric that proves the effect.

| Tier | Action | Native basis | Reversible | Verify | Exclusive | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| A | `cache.flush` | `FLUSH CACHE` | n/a (writes dirty pages) | none (unverified); I/O counters move | No | Short I/O spike; useful before an external copy |
| A | `cache.flushPeriodicity` | `SET DATABASE PARAMETER(Cache flush periodicity; s)` | Yes, session-only | `db.cacheFlushPeriodicity` (M2b) | No | Bounded values, e.g. 5–300 s |
| A | `cache.unloadMinimum` | `SET DATABASE PARAMETER(Cache unload minimum size; bytes)` | Yes, session-only | `db.cacheUnloadMinimum` (M2b) | No | Bounded to a fraction of `cache.maxMem` |
| A | `logs.diagnostic` | `SET DATABASE PARAMETER(Diagnostic log recording; 0/1)` | Yes | Read-back via `Get database parameter` | No | Support aid; writes to the host Logs folder |
| B | `datastore.writeFreeze` and `datastore.unlock` | `ds.flushAndLock()` / `ds.unlock()` | Yes; held state | `datastore.locked` (M1) | Yes | Max hold (e.g. 120 s) with automatic unlock; lock ownership is per process, so the same executor must unlock |
| B | `datastore.adminProtection` | `ds.setAdminProtection(bool)` | Yes | `datastore.adminProtected` (M1) | No | Security posture; persistence semantics to confirm |
| B | `datastore.requestLog` | `ds.startRequestLog` / `stopRequestLog` to a fixed file in Logs | Yes; held state | File exists and grows | No | The log can contain query contents: size cap, maximum duration, never exported |
| C | `backup.start` | `BACKUP` | No (consequential); async | `backup.*` metrics, which are **currently unsupported** (gate B0) | Yes | Needs gate B0 (host backup scope) first; long; progress |
| C | `journal.newLogFile` | `New log file` | No | Journal metadata (not yet collected) | Yes | Needs a journal read contract first |
| C | `server.messageUsers` | `SEND MESSAGE TO REMOTE USER` (fixed templates only) | No; outward-facing | Delivery not observable | No | Server only; no free text, to avoid phishing through the dashboard |
| C | `server.dropIdleSession` | `DROP REMOTE USER` by a session the monitor itself listed | No | `session.count` | No | Server only; needs real Server/client fixtures |

**Kept out of scope**, as the handover already decided: arbitrary
method, formula, SQL, shell, file or PID execution; web/SQL server
lifecycle; restore, compaction, repair, encryption and keys; schema and
index changes; license operations; restart or shutdown; and anything
reached through a selector or path supplied by a caller.

## 5. Compatibility with the existing periodic reports

| Report | Interaction | Required handling |
| --- | --- | --- |
| **Scheduled sampling (2/5/10 s, M4)** | Exclusive and heavy actions slow or block the cooperative collector | Non-fatal sample timeouts (3.2); pause for exclusive actions; cadence is never changed by an admin action |
| **Freshness (15 s stale rule)** | A paused stream would turn `stale` | New viewer status `maintenance`, distinct from `stale`; it returns to `stale` if the action outlives its deadline |
| **Live graphs and history (M5)** | Paused or busy samples leave holes; flushes cause I/O spikes | Holes remain **gaps** (already the rule). Add an anonymous **maintenance band** to history, `{from, to}` only, so a spike or hole is explained without revealing who did what |
| **Counters and rates** | Actions don't reset 4D counters, but a lock can stall them | Existing elapsed-time and reset rules apply unchanged |
| **Cached collector reads (encryption and backup 60 s; static info at start)** | Without care, a verified change would show the old value for up to 60 s | Invalidate the specific cache after a verified action (3.5) |
| **Static instance information** | Read once at start; tier A settings live in `db.*` and are re-read every sample (M2b) | No change; settings were made sample-time on purpose |
| **Refresh button** | Separate pending slot from actions | Still allowed during non-exclusive actions; answered `collector_busy` while paused |
| **Monitor diagnostics (M4)** | Should explain admin activity | Add counters: actions by tier and state, executor busy time, sample timeouts, pauses |
| **Audit (M3)** | Gains orphaned and denied outcomes | `host_denied`, `postcondition_unmet`, `orphaned` and automatic `undo` become audited states; the fail-closed rule is unchanged |

## 6. Phasing

| Phase | Content | Exit evidence |
| --- | --- | --- |
| **A0: foundations** (no new action) | Executor worker and async return path, epoch-keyed agent registry, non-fatal sample timeouts, shared catalog file, per-action deadlines, progress, `maintenance` pause, host `authorize` callback, TLS-or-loopback rule, native probe harness | Existing actions moved onto the executor with identical results. A deliberately slow fake action (`operator.sleep`, test catalog only) proves: refresh keeps working during a non-exclusive action; pause and resume for an exclusive one; the deadline gives `outcome_unknown`; a late result is not applied; CLI death gives `orphaned` in audit; sampler timeouts don't kill the monitor |
| **A1: tier A** | The four reversible, verifiable settings and flush | Each verified through its existing metric on tool4d and on full 4D 21 (your test project); `unverified` shown for flush |
| **A2: tier B** | Write freeze with automatic unlock, admin protection, request log with caps | Lock-hold expiry and an epoch end both release the lock; `host_denied` path; no request-log contents leave the host |
| **A3: tier C** | Backup, new log file, server messaging and session drop | Only after gate B0 (backup scope) and **real 4D Server/client fixtures**; each with its own contract and recovery plan |

## 7. Decisions needed from the owner

1. Is the host `authorize` callback acceptable as the authority model for tiers B and C?
2. Should tier A also require it, or is the operator token plus host allowlist enough there?
3. Should maintenance bands be visible to viewers (time span only), or to operators only?
4. Should tier B/C actions be allowed over LAN with TLS, or on loopback only?
5. Which tier C items matter at all? Each needs fixtures that the project doesn't have yet.
