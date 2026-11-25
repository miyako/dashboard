# Handover: continue `miyako/dashboard` on the Mac (local session)

Written 2026-11-25 at the end of a cloud session. The cloud session could not run 4D (Linux container), so everything below that needs a real 4D runtime is still open. The source of truth is GitHub, not this file: re-check it before acting.

## Start here (copy this into the local session)

> Take over `miyako/dashboard`. Read `AGENTS.md`, issue #29 (the handover and constraints) and `docs/log-browsing-design.md` first, then re-check `main`, releases, CI, issues and PRs, since they may have moved. Run `python3 scripts/doctor.py --root .`, then the local acceptance run, and report what `passed`, `failed` and `not_run`. After that continue with the open items in the order given in the section "What is left". One bounded change at a time, small PRs, only open a PR when I ask. Never bump a version, dispatch Build, create or move a tag, touch signing secrets or publish a release unless I explicitly say so.

## State at hand-off

| Item | Value |
| --- | --- |
| `main` | `8954de575e5a4588d1aa52b2fc570ac42157e8c2` (merge of #33). Re-check. |
| Latest release | `0.1.9`, published **unsigned**. Nothing was released, tagged or signed in this session. |
| Release policy | `release-policy.json` is `["*"]`: every future Build must be Apple-signed and notarized. Credentials are user-owned (see AGENTS.md). |
| Open PRs / issues | None opened by this session; #29 (the handover issue) is still open. |
| Compiler pin | tool4d 21.1, build 100562, macOS ARM (`package.json` `tool`). |

### Merged this session (all with green CI, including the hosted tool4d `assembly` job)

| PR | What |
| --- | --- |
| #30 | Docs reconciliation: README, class docs, package/template descriptions, design-doc status lines, AGENTS.md signing wording, `tests/test_playbook.py` no longer pins the README example tag. |
| #31 | **Log L2**: `4d.diagnostic` family (sensitive; needs the operator `authorize` formula, enforced at `start()`), exact-match level filter (`ERROR/WARN/INFO/DEBUG/TRACE`), host-local time jump, 8 MiB scan budget for filtered/time requests, virtualized viewer. |
| #32 | **Log L3**: `POST /api/operator/logs/search` (plain text, 64 MiB / 200 matches per request, 30 per minute, one in flight), authorized and audited per request through a `logAccess` frame with `op:"search"` and a keyed `queryDigest` (never the text), search panel in the UI. |
| #33 | README follow-up for L2/L3. |

Design notes for what was built are in `docs/log-browsing-design.md` ("L2 as built", "L3 as built").

### What was and was not verified

Verified (cloud, Linux): Python tests (278, 76 skipped), `go vet`, `go test -race`, Node tests (27), workflow contract, and a Chromium run (light/dark, 1100 px and 390 px) of the real Go CLI over the real stdin protocol with a synthetic diagnostic file and a Python stand-in for 4D. Hosted CI passed the new host-contract cases (strict frame checks, audit entries, sensitive-family `authorize` requirement) under macOS ARM tool4d.

**Not verified, so still `not_run`:**
- The diagnostic viewer, filter, time jump and search **through a real 4D host** (the host contract only tests the 4D-side validation and audit units; the browser path was tested against the CLI with a fake 4D).
- WARN/INFO/DEBUG/TRACE level names in real 4D logs. Only `ERROR` has ever been observed.
- `authorize` for these families on 4D Server; native Intel and Windows 4D hosts; real client/server; Dependency Manager install; signing/notarization; UTF-16 diagnostic files (they currently show replacement characters).

## Do this first on the Mac

```bash
git clone https://github.com/miyako/dashboard && cd dashboard   # or `git pull` in your checkout
git log --oneline -3                                            # expect 8954de5 or newer
python3 scripts/doctor.py --root .                              # read-only report
python3 -m pip install -r tooling/requirements-workflow.txt     # only if the workflow check complains
python3 -m unittest discover -s tests -v
python3 scripts/generate_icons.py --check
(cd cli && go test -race ./... && go vet ./... && node --check web/app.js && node --check web/charts.js && node --check web/operator.js)
node --test tests/test_charts.cjs tests/test_operator.cjs
python3 scripts/workflow_contract.py --root .
python3 scripts/ci_config.py download-tool4d --root .           # pinned 21.1, hash-verified, into .tools/
python3 scripts/accept_local.py --root . --repository miyako/dashboard \
  --tool4d .tools/tool4d.app/Contents/MacOS/tool4d --cross
```

Expectations: on Apple Silicon `accept_local.py --cross` builds all three Go targets, tests the native one, and ends with `result:"partial"`, `finished:true`, `release_ready:false` and `dist/dashboard.zip` plus `dist/dashboard.acceptance.json`. Intel and Windows stay `not_run` (Rosetta is translated execution, not native Intel). Go needs 1.23+; CI pins 1.26.10, so report the compiler you actually used. Copy the ZIP and acceptance JSON out of the worktree if you want to keep them.

Extras: `DASHBOARD_LARGE_LOG=1 go test -run SearchScanBudget ./...` in `cli/` runs the 1 GiB search budget test (about 3 s here).

## What is left (in order)

1. **Local acceptance on the Mac** (above). Record the evidence: revision, tool4d version/hash, per-check status.
2. **Log L0 on real 4D, with disposable synthetic data only.** Use `scripts/probe_native.py` and isolated projects. Open questions, from `docs/log-browsing-design.md` section 2:
   - the real level names in `4DDiagnosticLog*` (WARN/INFO/DEBUG/TRACE), multi-line messages, localized text, UTF-8 vs UTF-16, very long lines;
   - `4DRequestsLog*` and the process-info log (these are written only by **4D Server**; needs a Server fixture);
   - backup journal names and formats (needs a data file and a backup; never start backups on user data).
   Record platform, version and behavior for each. Do not call database parameter selectors 114/115 (they crashed tool4d 21.1).
3. **A live 4D test of L2/L3**: add a host test that starts `Dashboard` with `logs` families `dashboard.audit,4d.diagnostic` and an `authorize` formula, writes synthetic lines to the host's diagnostic log, then drives open, filter, jump and search over HTTP and checks the audit trail. Today the live host test (`/logLive` in `tests/host/contract.json`) covers the audit family only.
4. **Log L4** (debug, request, TCP/UDP families behind `authorize`) only after real fixtures exist and the owner confirms the families. HTTP/web, HTTP client, mail and ORDA logs stay excluded (Logweb contains cookies).
5. **More aggregate metrics** (roadmap 2e): safe datastore physical/table/index summaries, owned CLI health. Check units and 21 LTS availability against the official 21 docs and a real runtime; the `miyako/skills` lookup corpus is **21 R5 BETA**, not proof for 21 LTS.
6. **Further administration**, one action at a time, only with owner approval (`docs/admin-actions-design.md`). Stateful locks need same-owner release and cleanup on error, timeout, stop and restart. Backup/journal/server operations need proven host targeting.
7. **Deployment evidence**: normal IDE/Server loading, real client/server, Dependency Manager install, native Intel and Windows 4D. Record unavailable ones as `not_run`.
8. **Final review and handoff**, with the AGENTS.md evidence matrix.

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
