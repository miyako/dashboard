# Log browsing: design (#19, part 2)

Status: **design accepted** (section 10 records the decisions). **L1 is implemented**: the
`dashboard.audit` family only, with the file map, open, paging and follow, and the fail-closed
`logAccess` round-trip. L0 is **partly done**: a disposable full 4D 21.2 standalone probe (section 2) confirmed the diagnostic/debug formats; Server request/process and backup-journal logs are unconfirmed. **L2 is implemented** (see "L2 as built" at the end of section 9): the `4d.diagnostic` family with a level filter, jump to time and a windowed viewer. L3–L4 are not started.

Found while implementing L1: `Folder(fk logs folder; *).path` returns the filesystem alias `/LOGS/`,
not a real path, so the component converts `platformPath` to POSIX. A headless tool4d project's Logs
folder is under `~/Library/Application Support/tool4d/<project>/Logs`. Routes live under
`/api/operator/logs/`, because the operator cookie is scoped to `/api/operator/`. "Tail" is a
forward page from the `after` cursor. It builds on operator mode (M3),
the shared catalog pattern (A0), the host `authorize` callback (A0/A1) and the restart strategy.

## 1. Why this is the riskiest feature so far

Every earlier feature exports **allowlisted fields only**. Logs are the opposite: free text written
by 4D, and by the application through `LOG EVENT`, which can contain anything. From the 4D 21 log
reference (`developer.4d.com/docs/Debugging/debugLogFiles`):

| Family | What it can expose |
| --- | --- |
| Request log (`4DRequestsLog`) | SQL text, ORDA dataclass and attribute names, the OS login and hostname of the 4D user |
| Request process info (`4DRequestsLog_ProcessInfo`) | Client IP addresses, host names, user names, process names |
| Debug log (`4DDebugLog`) | **Command and method parameter values**, method names, `LOG EVENT` text |
| Diagnostic log (`4DDiagnosticLog`) | `LOG EVENT` text, socket and task details |
| TCP/UDP log | Peer addresses, and the first 10 bytes of every payload |
| HTTP server debug log (`HTTPDebugLog`) | **Full HTTP headers (cookies, `Authorization`) and optionally bodies** |
| HTTP client log (`4DHTTPClientLog`) | **Outgoing headers (API keys) and bodies** |
| SMTP / POP3 / IMAP logs | **Authentication exchanges**, mail headers, attachments (extended) |
| ORDA request logs | Request URLs and **entity data in response bodies**, user names, IPs; written **anywhere** the developer chooses |

Redacting free text reliably is not possible, and this design does not claim to. Instead it
**limits who can read, what can be read, and records who read what**.

## 2. What real files look like (measured, tool4d 21.1)

A throwaway headless project enabled the diagnostic and tabular debug logs (`scripts/probe_native.py`):

```
Logs/4DDiagnosticLogTool_1.txt   (not the documented 4DDiagnosticLog.txt)
33 2026-11-15T11:57:46.101 [tool4d.APPL] ERROR - dashboard probe message one ()

Logs/4DDebugLogServer_1.txt      ("Server" even under tool4d; tabular mode 2+4)
-- Startup on: Sunday, November 15, 2026 11:57:46 AM --
sequence_number	time	processID	...	operation	operation_parameters	...
5	2026-11-15T11:57:46.101	1	1	0	1	1509	Undefined	0
```

What this means for the design:

- **Names vary.** A product suffix (`Server`, `Tool`, none) and a rotation index (`_1`, `_2`…) are
  appended. Families are matched by anchored patterns on the **base name only**, and rotated
  siblings are grouped.
- **Formats vary.** The diagnostic log is space-delimited, as `seq time [component] LEVEL - message`.
  The tabular debug log is a free-text banner, then a TSV header, then rows. Some logs are
  JSON Lines.
- **Timestamps have no time zone.** Any jump-to-time must use the host's local time and say so.
- **Encoding.** These samples are ASCII/UTF-8. Invalid bytes become U+FFFD, and a UTF-16 BOM is
  decoded. Each displayed line is capped at 16 KiB, with an explicit truncation marker.
- Still **to confirm** on full 4D: the web access log and backup journal names and formats, which
  the reference page does not cover.

### L0 results on full 4D 21.2 (build 21.100653, standalone, 2026-11-15)

Run through the local test host (`dashboard-testhost`, `Native_logs_l0`), in a throwaway, data-free
copy, with synthetic events only:

| File | Observed | Consequence |
| --- | --- | --- |
| `4DDiagnosticLog_1.txt` | No product suffix on standalone 4D (tool4d adds `Tool`). `seq time [component] LEVEL - message`. 4D's own messages are **localized** (Japanese here, multibyte UTF-8) and can include IP addresses. The file **keeps lines from earlier runs** | Pattern `^4DDiagnosticLog(Server\|Tool)?(_\d+)?\.txt$` confirmed; sensitive, as planned; UTF-8 handling is required |
| `4DDebugLog_1.txt` | The tabular format matches tool4d. `operation_parameters` contains the exact `LOG EVENT` text and command arguments | Confirmed sensitive; host approval required |
| `Logweb.txt` | WLF format with a `#Fields:` header that includes **`cs(cookie)`**, plus `c-ip`, `cs(user-agent)`, `cs-uri-query` and `cs(host)` | **Secret-bearing (session cookies): moved to the excluded families**, not opt-in |
| `4DRequestsLog` | Not written by standalone 4D (4D Server only) | Needs a 4D Server fixture before L4 |
| Backup journal | Needs a data file and a backup | Still to confirm, with a data-file fixture |

Also measured: the Logs folder sits outside the project copy, so it persists across runs and tests
must not assume it is empty. Host targeting of the web server is confirmed on full 4D (the collector
reads the host's server, not the component's). `WEB Server.start()` needs `IPAddressToListen` as a
**collection**; a text value fails with error 1029.

## 3. Architecture: the CLI reads, 4D authorizes and audits

```
Browser (operator session) ──▶ CLI /api/logs/*  ──read-only──▶ host Logs folder (confined)
                                   │  logAccess frame (open, search)        ▲
                                   ▼                                         │
                                4D agent ── authorize(host formula) ── audit.jsonl (fail-closed)
```

**Why the CLI reads files directly, not 4D:**
- Logs can be hundreds of MB. Paging through 4D would block the cooperative worker and compete with
  sampling (the exact failure mode A0 fixed).
- It would also run into the 256 KiB frame limit.
- Go seeks and scans files cheaply, in bounded memory.

**What 4D still owns:**
- Turning the feature on.
- The folder: it sends the host's resolved Logs folder at start (`--logs-root`). Like the
  operator token, it never comes from a browser.
- The families allowed (`--log-families`).
- **Authorization and audit:** before a file is opened or searched, the CLI sends a `logAccess`
  frame and waits up to 5 s for 4D's `logAccessResult`. 4D calls the host `authorize` formula when
  the family requires it, writes the audit record, and answers. **No answer, a denial or an audit
  failure means nothing is served.** This is the same fail-closed rule as actions.

**Confinement in the CLI** (defense in depth; the process already runs as the 4D user):
- Only base names under the given root, matching a family pattern. No `/`, `\`, `..` or NUL.
- `Lstat` refuses symlinks, directories and special files.
- `open` then `fstat`, then `os.SameFile` against the `Lstat` result, which closes the
  swap-after-check window.
- Read-only handles, never written, never deleted. The root itself must not be a symlink.

## 4. Closed family catalog

A `cli/logs.json` catalog (byte-identical copy in the component, like `actions.json`):

| Family | Pattern (base name) | Format | Sensitivity | Default |
| --- | --- | --- | --- | --- |
| `dashboard.audit` | `^audit(\.[1-3])?\.jsonl$` in `Logs/dashboard/` | JSON Lines | normal | first family to ship |
| `4d.diagnostic` | `^4DDiagnosticLog(Server\|Tool)?(_\d+)?\.txt$` | `seq time [component] LEVEL - message` | sensitive | opt-in |
| `4d.debug` | `^4DDebugLog(Server\|Tool)?(_\d+)?\.txt$` | banner, TSV header, rows | **sensitive (parameters)** | opt-in, `authorize` required |
| `4d.requests` | `^4DRequestsLog(Server)?(_\d+)?\.txt$` | header, TSV | **sensitive (SQL, logins)** | opt-in, `authorize` required |
| `4d.requests.process` | `^4DRequestsLog_ProcessInfo(Server)?(_\d+)?\.txt$` | header, TSV | **sensitive (IPs, users)** | opt-in, `authorize` required |
| `4d.tcpudp` | `^4DTCPUDPLog(_\d+)?\.txt$` | TSV-like | sensitive (payload bytes) | opt-in, `authorize` required |
| **excluded** | `HTTPDebugLog*`, `4DHTTPClientLog*`, `4DSMTPLog*`, `4DPOP3Log*`, `4DIMAPLog*`, ORDA request logs, **`Logweb*.txt` (WLF logs cookies; L0)** | | **secret-bearing** | not offered |

Excluded families cannot be listed: their names never match a catalog pattern. Offering them would
need a separate decision with its own controls; masking HTTP headers is not a promise this design makes.

## 5. API (operator session, same CSRF, origin and body rules as `/api/operator/*`)

| Route | Purpose | Bounds |
| --- | --- | --- |
| `GET /api/logs/files` | **File map**: `{id, family, name, size, modified, rotationIndex}` per allowed file; base names only, never paths | At most 256 files; re-listed on demand |
| `POST /api/logs/open` | `{file}` → authorization and audit, then a **view token** and the first page | 1 open view per session (a new open replaces it); the view expires with the session |
| `GET /api/logs/page?view&cursor&direction&limit` | **Paging and infinite scroll** in both directions | At most 500 lines and 256 KiB per response |
| `POST /api/logs/search` | `{view, text, caseInsensitive, field?, direction, from}` → audited, then matches with cursors | Plain substring only; at most 200 matches; **scan budget 64 MiB per request**, with a continuation cursor; 1 in flight, 30 per minute per session |
| `GET /api/logs/tail?view&cursor` | New lines after the cursor (**follow**), polled every 2 s | Same page bounds |

- **File ids:** HMAC(per-process key, device + inode + birth time + name). They're opaque,
  unforgeable, and change with a CLI restart, so old cursors are dead.
- **Cursors** are HMAC-signed `{file id, byte offset at a line start, file size when issued}`.
  - A **rotated** file (its id no longer resolves) answers 410 `rotated`.
  - A **truncated** file (size below the offset) answers 410 `truncated`.
  - The browser then reopens from the map. A cursor is never silently remapped to other data.
- **Line index cache:** a sparse map of byte offset to line number, one checkpoint per 64 KiB, kept
  per open file. It's an LRU over files, limited to 4 MiB in total. It gives line numbers and fast
  jumps to a percentage; for timestamped families it also allows **jump to time** by binary search
  over checkpoints.
- **Filters:** only on parsed columns of the family format (diagnostic `level`, debug
  `operation_type`, request `request`). They are exact matches on a closed list per family, never
  expressions.
- **No regular expressions:** they invite slow scans on large files, and plain text covers the need.
- **No download or export** in the first version: copying is per line, from the screen.

## 6. Browser

- A **Logs** tab, visible only to operator sessions. Viewers never see it, and nothing about logs
  enters the shared SSE state.
- **File map** with family, size, modification time and rotation grouping, with the newest first.
- **Viewer:**
  - a virtualized list (about 200 DOM rows whatever the file size), infinite scroll both ways
  - Start, End, jump to % or time (labelled "host-local time")
  - a follow toggle (tail polling)
  - wrap and copy line
  - a column view for TSV families
- **Search:** next, previous, a match count with a "scanned 64 MiB, continue?" prompt, and
  highlighting with text nodes only (never `innerHTML`).
- **Client cache:** at most 2000 lines in memory, with far pages evicted. **Nothing is stored in
  browser storage**, because logs must not persist on viewer machines.
- **Accessibility:**
  - keyboard paging (PgUp, PgDn, Home, End)
  - match counts announced through `aria-live`
  - the truncated-line marker is spoken text, not only a glyph

## 7. Robustness and compatibility

| Concern | Handling |
| --- | --- |
| Sampling and 4D load | Files are read by Go, never 4D; 4D only answers `logAccess` (open and search, not every page) |
| Waiting for 4D | The handler waits for `logAccessResult` **outside** the service lock, at most 1 pending `logAccess` per session; the stream, refresh and actions are never blocked by a log open |
| CLI memory | Page, scan and index budgets as above; every response is capped |
| Huge or binary files | The scan budget bounds the work; a NUL-heavy page is shown as binary, and the view refuses after 3 such pages |
| Concurrent writes by 4D | Appends are visible through tail; a partial last line is held back until a newline arrives |
| Rotation during reading | 410 `rotated` or `truncated`, then reopen; no silent remap |
| CLI restart | View tokens, cursors and file ids die with the old process (new HMAC key); the browser reopens |
| Restart strategy | Unaffected; log reads add no liveness risk (HTTP handlers, not the pipe) |
| Remote clients | The Logs folder is the collecting instance's; on a remote client that is the client's folder, labelled as such |
| Operator actions and audit | `logAccess` audit records use the same `audit.jsonl`, with action `logs.open` or `logs.search`, a hashed file id and a hashed search text (never the text) |

## 8. Privacy and security summary

1. Off by default. The host must list families, and the sensitive ones need an `authorize` formula.
2. Operator session only; TLS or loopback only, as for tier B and C actions.
3. Only a closed list of families can be read, and secret-bearing logs are never offered.
4. Every open and every search is authorized by the host and audited before any byte is served.
5. Confinement, symlink and swap checks, read-only handles.
6. Bounded responses, no regular expressions, no export, no browser persistence.
7. Search text is hashed in the audit, so the audit does not become a copy of what people looked for.

## 9. Phases

| Phase | Content | Exit evidence |
| --- | --- | --- |
| **L0** | Contract and catalog; **confirm on full 4D** (your 4D 21 R4 project) the names and formats of the diagnostic, debug, request, web access and backup logs | A probe on full 4D; catalog patterns tested against real names |
| **L1** | File map, open, paging and tail for `dashboard.audit` only; the `logAccess` frame; confinement tests (traversal, symlink, swap, rotation, truncation) | Go tests, including a symlink-swap race; live tool4d reading its own audit; 410 on rotation |
| **L2** | `4d.diagnostic` with level filter and jump to time; the virtualized viewer | Real diagnostic logs from tool4d (probe-generated); the UI on the mock harness |
| **L3** | Search with budget and continuation | Large synthetic files (1 GiB) stay within the memory and time budgets |
| **L4** | Sensitive families (`4d.debug`, `4d.requests`, `4d.tcpudp`) behind `authorize` | Denial paths, audit of each open and search |

### L2 as built

- `cli/logs.json` gains `4d.diagnostic` (`dir: ""`, i.e. the Logs folder itself; `sensitivity: sensitive`;
  `parse: "diagnostic"`). The component refuses to start it without an operator `authorize` formula, and
  `logAccess` still denies a sensitive family when no formula is present.
- Page requests accept `level` (exact match on `ERROR|WARN|INFO|DEBUG|TRACE`) and, instead of a cursor,
  `time` (`YYYY-MM-DDTHH:MM[:SS[.mmm]]`, host-local, no zone). Anything else is a 400; both are refused on
  a family without a parser (`unsupported_filter`). A level filter hides lines that do not parse
  (the banner, multi-line continuations).
- Filtered pages and the jump examine at most 8 MiB per request (`limited: true` plus a continuation
  cursor when the budget ends first). Backward filtered scans read 256 KiB blocks. A time jump is a
  binary search over byte offsets, then a short linear scan; it assumes timestamps do not go backwards,
  so after a host clock change it returns the nearest line it can reach. Opening, filtering and jumping
  are covered by the single audited open; they are not audited again.
- The browser list is virtualized with fixed 20 px rows (about 50 rows in the DOM for 2000 in memory).
  The "wrap" option of section 6 was **not** built, since wrapping needs variable row heights; long lines
  scroll sideways. Line numbers (the sparse index of section 5) were not built either.
- Verified here: Go tests (parsing, filters in both directions, 3000-line time search against a reference,
  20 MiB scan budgets, multibyte and over-long lines, validation), Node tests for the window arithmetic,
  and a real-browser run (Chromium, light and dark, 1100 px and 390 px) of the real CLI over the real stdin
  protocol with a **synthetic** diagnostic file. Not verified: real 4D diagnostic logs beyond the earlier
  probe, WARN/INFO/DEBUG/TRACE names in real files, a 4D host calling `authorize` for this family on
  Server, UTF-16 files (they would show replacement characters), Intel/Windows hosts.

## 10. Owner decisions (recorded: the recommended defaults were accepted)

| # | Question | Decision |
| --- | --- | --- |
| 1 | Who reads | The CLI reads files directly from the confined host Logs folder; 4D authorizes and audits |
| 2 | Audit granularity | Every **open** and **search**, fail-closed; paging within an opened view is not audited per page |
| 3 | Sensitive families | `4d.debug`, `4d.requests`, `4d.requests.process` and `4d.tcpudp` require the host `authorize` formula. HTTP debug, HTTP client, SMTP/POP3/IMAP and ORDA logs stay excluded |
| 4 | Network | TLS or loopback only, like tier B and C actions |
| 5 | Export | No download or export in the first version |

### Original questions

1. **Who reads:** do you agree the CLI reads files directly, with 4D authorizing and auditing each
   open and search? Recommended.
2. **Audit granularity:** open and search only (recommended), or every page?
3. **Sensitive families:** require `authorize` for debug, requests and TCP/UDP (recommended)? And
   keep HTTP, mail and ORDA logs excluded entirely?
4. **Network:** TLS or loopback only, like tier B and C (recommended)?
5. **Export:** no download in the first version (recommended)?
