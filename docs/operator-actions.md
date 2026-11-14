# Operator action contract (M3)

Status: substrate only. The single action, `operator.noop`, changes nothing.
Operator mode is **off by default**; no high-risk mutator exists.

This contract was written before the implementation and is the reference for
both the Go CLI (`cli/operator.go`) and the 4D component
(`_DashboardOperator.4dm`). Owner decisions recorded here:

| Decision | Choice |
| --- | --- |
| Operator credential | A second, independent 256-bit operator token minted by the CLI, delivered only to the host's `onStatus` callback as `operatorUrl` |
| Audit location | Host `Logs` folder: `Logs/dashboard/audit.jsonl`, rotated at 1 MiB, 4 files kept |
| Limits | Operator session 15 min idle / 60 min absolute; confirmation 60 s, single use; 1 action in flight; 6 action requests per minute; 30 s action timeout |
| Exercising action | Built-in `operator.noop`, enabled only when the host lists it; two-step browser confirmation |

## 1. Opt-in and negotiation

- Host code opts in explicitly:
  `start(New object("operator"; New object("actions"; New collection("operator.noop"))))`.
  Without `operator`, the CLI starts with no operator token and every
  `/api/operator/*` route answers 404. Viewer behavior is unchanged either way.
- `operator` accepts only `actions`: a collection of 1..8 unique IDs from the
  closed catalog. Anything else fails `start()`.
- The component passes `--operator-actions <comma list>`. The CLI validates
  each ID against its own closed catalog.
- The CLI's `ready` frame adds `operator: {version: 1, actions: [...]}` and
  `operatorUrl` (`<origin>/#token=<viewer>&operator=<operator token>`). The
  component rejects a `ready` whose operator actions differ from what it
  requested, or whose URL does not match the strict pattern.
- The component's `hello` adds `operator: {version: 1, actions: [...]}`. The CLI
  rejects a hello that declares operator mode it did not enable, omits operator
  mode it did enable, or lists different actions. Protocol 1 refresh frames are
  unchanged and are never reinterpreted as actions.

## 2. Authority

- Authority comes only from the operator token. It is never inferred from the
  viewer cookie, Designer, 4D users/groups, WebAdmin, Data Explorer or Session
  privileges.
- `POST /api/operator/session` with `{"token": "..."}` (constant-time compare)
  creates a per-browser operator session: an `HttpOnly`, `SameSite=Strict`
  cookie scoped to `/api/operator/`, `Secure` under HTTPS. At most 4 sessions;
  15 minutes idle and 60 minutes absolute expiry. The viewer cookie is also
  required.
- The audit **actor** is the first 16 hex digits of SHA-256 of the session ID:
  stable per browser session, not reversible, and not a person's identity.

## 3. Requests

Every operator `POST` needs the viewer cookie, the exact `Origin`, header
`X-Dashboard-Action: operator`, `Content-Type: application/json`, a body of at
most 1024 bytes holding exactly one JSON object, and no unknown fields.

| Route | Body | Effect |
| --- | --- | --- |
| `POST /api/operator/session` | `{"token"}` | Create operator session (no operator cookie needed) |
| `GET /api/operator/status` | — | Enabled actions, generation, this actor's confirmations and recent actions |
| `POST /api/operator/request` | `{"action", "args"}` | Validate, then issue a confirmation (`requested`) |
| `POST /api/operator/confirm` | `{"confirmation", "action", "args"}` | Consume the confirmation; dispatch (`accepted`) |
| `POST /api/operator/cancel` | `{"id"}` | Withdraw a `requested` action (`cancelled`) |
| `POST /api/operator/logout` | `{}` | End this operator session; its confirmations are cancelled |

- Unknown action ID: 400. Catalog action not enabled by the host: 403
  (default deny).
- `operator.noop` args: exactly `{"note": "<1..32 of A-Z a-z 0-9 space _ . ->"}`.
- Rate: at most 6 `request` calls per rolling minute and 4 outstanding
  confirmations; otherwise 429.

## 4. Confirmation

A confirmation binds **actor, action, canonical arguments, epoch, generation
and expiry (60 s)**. It is consumed on the first `confirm` attempt, whether
that attempt succeeds or not. `confirm` fails, and the action becomes
`cancelled` with a reason code, when any of these differ or hold:

| Reason | Condition |
| --- | --- |
| `unknown_confirmation` | Never issued, already used, or withdrawn (no record changes) |
| `wrong_actor` | Another operator session presents it |
| `expired` | Past its expiry |
| `argument_mismatch` | Restated action or canonical arguments differ |
| `stale_target` | Epoch changed, generation advanced, or the stream is stale |
| `busy` | Another action is already in flight |

**Generation** advances whenever an action finishes, times out, or the stream
becomes stale. It does not follow the metric sequence, which advances every
sample. A confirmation issued before another action finished cannot be used.

## 5. Dispatch and states

`requested → accepted → running → completed | failed`, and
`requested → cancelled`.

- `accepted` means the CLI wrote the action frame. **It is not a postcondition.**
- CLI → 4D: `{"protocol":1,"kind":"action","epoch","id","action","args","actor"}`.
  `id` is a fresh 64-hex value; the component rejects a wrong epoch, an
  unknown action, unknown fields, or a duplicate `id`.
- 4D → CLI: `actionState` frames carrying `id`, `state` (`running`,
  `completed` or `failed`) and, when failed, an `error` code (`[a-z_]{1,64}`).
  `completed` may carry only `audit_incomplete`; `running` carries none.
- In flight beyond 30 s → `failed` with `outcome_unknown`, because it may still
  have run. A later result is recorded as `lateState` and never changes the
  state again. Duplicate and late frames for recent IDs (last 32) are ignored;
  frames for unknown IDs are protocol errors.
- No automatic retry. Dispatched actions cannot be cancelled in M3, because
  `operator.noop` is atomic. Interruptible actions must define their own
  cancellation when they are added.
- Refresh and actions use separate pending slots and do not block each other.

## 6. Audit

- The component appends one JSON line per transition it handles (`running`,
  `completed`, `failed`) to `Logs/dashboard/audit.jsonl` in the **host**'s Logs
  folder. When the file reaches 1 MiB it rotates to `audit.1.jsonl` ..
  `audit.3.jsonl`, and the oldest is deleted.
- Record: `{"v":1,"at":<UTC>,"epoch","action","id":<sha256(id) 16 hex>,"actor","args":<sha256(canonical args) 16 hex>,"state"}`.
  No tokens, cookies, nonces, URLs, raw arguments or native payloads.
- **Fail closed:** if the `running` record cannot be written, the action is not
  executed and fails with `audit_unavailable`. If the final record cannot be
  written, the action's state is reported and `audit_incomplete` is added.
- Confirmation lifecycle events (issued, withdrawn, rejected) are not
  audited, because nothing was dispatched to 4D.

## 7. Never

No arbitrary method, formula, SQL, shell, file, PID, session or selector
execution. No action results in SSE: viewers see nothing new. Operator status
is served only to operator sessions and lists only that actor's actions.
