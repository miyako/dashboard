# Handover: continue `miyako/dashboard` on the Mac (local session)

Written 2026-11-25 at the end of a cloud session; refreshed 2026-11-26 after the local Mac session. The cloud session could not run 4D (Linux container), so everything below that needs a real 4D runtime is still open. The source of truth is GitHub, not this file: re-check it before acting.

## Start here (copy this into the local session)

> Take over `miyako/dashboard`. Read `AGENTS.md`, issue #29 (the handover and constraints) and `docs/log-browsing-design.md` first, then re-check `main`, releases, CI, issues and PRs, since they may have moved. Run `python3 scripts/doctor.py --root .`, then the local acceptance run, and report what `passed`, `failed` and `not_run`. After that continue with the open items in the order given in the section "What is left". One bounded change at a time, small PRs, only open a PR when I ask. Never bump a version, dispatch Build, create or move a tag, touch signing secrets or publish a release unless I explicitly say so.

## State at hand-off (refreshed 2026-11-26, local Mac session)

| Item | Value |
| --- | --- |
| `main` | `b7ab728` (merge of #39). Re-check. |
| Latest release | `0.1.9`, published **unsigned**. Nothing was released, tagged, bumped or signed in either session. |
| Release policy | `release-policy.json` is `["*"]`: every future Build must be Apple-signed and notarized. Credentials are user-owned (see AGENTS.md). |
| Compiler pin | tool4d 21.1, build 100562, macOS ARM (`package.json` `tool`). Local run used Go 1.27.4 (CI pins 1.26.10). |
| Open issue | #29 (the handover issue). No open PRs from this work. |

### Merged in the local session (all with green CI, including the hosted tool4d `assembly` job)

| PR | What |
| --- | --- |
| #35 | Live L2/L3 host test (`/logDiagLive`: synthetic diagnostic file, WARN filter, time jump, search, host `authorize` calls, audit digests, no query text in audit); `lipo -verify_arch` one architecture per call (newer lipo rejects the variadic form); L0 observations from tool4d 21.1 and 4D Server 21.2 in `docs/log-browsing-design.md` |
| #36 | Roadmap 2e part 1: `schema.tables`, `schema.fields`, `schema.indexedFields` (classic structure commands, 60 s cache, 512 table / 65536 field caps, remote unsupported). Real data host reports 1/5/2; a dataless open reports 0 indexed fields |
| #37 | Roadmap 2e part 2: owned CLI health, five `cli.*` gauges added by the Go process to every sample (reserved prefix, not forgeable or deletable by 4D); history series cap 72 |
| #38 | Docs: exploratory 4D Server 21.2 run of the compiled package: smoke test completes, `web.*` fields available, host-versus-component targeting passes |
| #39 | Docs: Dependency Manager install of the published 0.1.9 release (plus `workers` 20.0.23, `tcp` 20.0.14) on 4D Server 21.2: `loaded` and `found`, bundled CLI runs |

### Evidence matrix (revision `main` after #37, tool4d 21.1 build 100562, macOS ARM)

`accept_local.py --cross`: `result:"partial"`, `finished:true`, `release_ready:false`.

| Check | Status |
| --- | --- |
| Python unit, icons, workflow contract | passed |
| Go `vet` and `test -race`, Node tests | passed |
| CLI build, three Go targets | passed |
| CLI test, macOS ARM native | passed |
| CLI test, macOS Intel and Windows (native), Rosetta | not_run |
| Assembly, source host, compile, package, compiled host (tool4d) | passed |
| 4D Server 21.2, compiled package smoke test | exploratory only (exit 139 after `QUIT 4D`; contract is tool4d-specific) |
| Dependency Manager install, Server 21.2 macOS ARM, unsigned 0.1.9 | passed (install and CLI launch only) |
| 4D IDE, real clients, Windows 4D, native Intel 4D | not_run |
| Signing and notarization | not_run (0.1.9 predates signing) |

Observations worth keeping: `LOG EVENT` has only info/warning/error severities (DEBUG/TRACE cannot be produced from it);
`Diagnostic log level` must be set before recording starts; a new run appends to the same diagnostic file and restarts its
sequence; 4D Server's request and process-info logs are TSV with a banner that carries the host name and OS login name.

## What is left

1. **Log L4** (requests and process-info logs behind `authorize`, then debug/TCP-UDP). Blocked on an owner decision: may host
   and user names be shown to an authorized operator? Needs parsers for both TSV formats and a catalog entry for the
   process-info log. HTTP/web, HTTP client, mail and ORDA logs stay excluded (Logweb contains cookies).
2. **Backup journals** (L0): needs a disposable data file and a backup; synthetic project only, never user data.
3. **Further administration**, one action at a time, only with owner approval (`docs/admin-actions-design.md`).
4. **More deployment evidence**: the live monitoring service on 4D Server with a real data file and real clients, the 4D
   IDE, Windows and native Intel 4D. Record unavailable ones as `not_run`.
5. **Hosted CI, signing and release**: a signed Build is the owner's call (secrets are user-owned; never dispatch Build or bump
   a version without explicit instruction).
6. **UTF-16 diagnostic files** (shown with replacement characters) and **DEBUG/TRACE lines written by 4D itself** remain unobserved.

## Constraints to keep (condensed from #29 and AGENTS.md)

- Monitoring stays read-only; operator mode is off by default, closed action catalog, host allowlist, per-action authorization, single-use confirmations, audit before action (fail closed), no arbitrary method/SQL/shell/path/PID/session execution, **never auto-retry non-idempotent actions** (timeout means `outcome_unknown`).
- Rejected proposals in #20 stay rejected. License refresh stays excluded. Backup metrics stay unsupported until a real host proves data-file targeting.
- Logs are sensitive free text: operator-only, family-allowlisted, host-authorized and audited, confined to the host Logs folder, no export, no generic redaction claim. Do not put real logs in issues, artifacts, tests or screenshots.
- Protocol: versioned UTF-8 NDJSON, 256 KiB frames, stdout protocol only, stderr diagnostics only. CLI and component versions must match (a search frame is rejected by an older component).
- Keep `cli/logs.json` and `component/dashboard/Resources/logs.json` byte-identical (there is a test). Keep `tests/host/contract.json` in step with `Smoke.4dm`.
- Every headless 4D project needs `Project/Sources/dependencies.json` before first open.
- Versions, tags, Build dispatch, signing policy and secrets are the owner's; component tags are prefix-free (`0.1.9`, never `v0.1.9`). Only the user runs `scripts/set-release-secrets.sh`.
- Report evidence as `passed` / `failed` / `not_run`; a partial local package is never release-ready.

## Useful facts learned in this session

- `Folder(fk logs folder; *).path` is a filesystem alias (`/LOGS/`), so the component converts `platformPath`. tool4d writes `4DDiagnosticLogTool_1.txt` and `4DDebugLogServer_1.txt`-style names; the Logs folder persists across runs, so tests must not assume it is empty.
- The 4D agent treats a malformed `logAccess` frame as fatal (`fail` + `stop`), by design.
- `tests/test_playbook.py` previously pinned the README example tag; it now accepts any SemVer tag.
- `operatorCall` in `cli/web/app.js` now throws errors carrying `status` and `code`; log errors map through `DashboardOperator.logReason`.

## Appendix: browser test harness (not committed)

To look at the UI without 4D, run the real CLI and let a small script play 4D over stdin/stdout, then drive Chromium with Playwright. The stand-in below worked; it needs a built CLI binary (`cd cli && go build -o /tmp/dash .`). Run: `python3 -W ignore fake4d.py /tmp/logs-root /tmp/dash`, then open the URL it prints (it is an operator URL, so treat it as a secret). All log content it generates is synthetic.

```python
import json, subprocess, sys, threading, time, datetime, os
root = sys.argv[1]
os.makedirs(root + "/dashboard", exist_ok=True)
levels = ["INFO", "ERROR", "WARN", "DEBUG"]
t0 = datetime.datetime(2026, 11, 15, 10, 0, 0)
with open(root + "/4DDiagnosticLogTool_1.txt", "w", encoding="utf-8") as f:
    f.write("-- synthetic banner --\n")
    for i in range(6000):
        at = (t0 + datetime.timedelta(seconds=30 * i)).strftime("%Y-%m-%dT%H:%M:%S.000")
        f.write(f"{i+1} {at} [synthetic.APPL] {levels[i % 4]} - message {i} 日本語 synthetic only\n")
open(root + "/dashboard/audit.jsonl", "w").write('{"v":1,"n":1}\n')
p = subprocess.Popen([sys.argv[2], "serve", "--listen", "127.0.0.1:0", "--operator-actions", "operator.noop",
                      "--logs-root", root, "--log-families", "dashboard.audit,4d.diagnostic"],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
seq = [0]
def send(kind, **kw):
    seq[0] += 1
    m = {"protocol": 1, "kind": kind, "epoch": "e1", "seq": seq[0],
         "sampledAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")}
    m.update(kw)
    p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
ready = json.loads(p.stdout.readline())
print(ready["operatorUrl"], flush=True)
send("hello", operator={"version": 1, "actions": ["operator.noop"]},
     logs={"version": 1, "families": ["4d.diagnostic", "dashboard.audit"]})
threading.Thread(target=lambda: [print("STDERR", l, file=sys.stderr, flush=True) for l in p.stderr], daemon=True).start()
def ticker():
    while p.poll() is None:
        time.sleep(2)
        try: send("snapshot", metrics=[])
        except Exception: return
threading.Thread(target=ticker, daemon=True).start()
for line in p.stdout:
    m = json.loads(line)
    if m.get("kind") == "logAccess":
        print("ACCESS", m["op"], m["family"], m["file"], flush=True)
        send("logAccessResult", id=m["id"], ok=True)
```
