package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type logsFixture struct {
	t     *testing.T
	s     *service
	c     *client
	root  string
	audit string
}

func newLogsFixture(t *testing.T) *logsFixture {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "dashboard")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	audit := filepath.Join(dir, "audit.jsonl")
	var lines []string
	for i := 1; i <= 150; i++ {
		lines = append(lines, fmt.Sprintf(`{"v":1,"n":%d}`, i))
	}
	// The last line has no newline yet: it must be held back.
	write(t, audit, strings.Join(lines, "\n")+"\n"+`{"v":1,"partial":true}`)
	write(t, filepath.Join(dir, "audit.1.jsonl"), "old\n")
	write(t, filepath.Join(dir, "audit.9.jsonl"), "not in catalog\n")
	write(t, filepath.Join(root, "other.txt"), "not in catalog\n")
	outside := filepath.Join(t.TempDir(), "secret.txt")
	write(t, outside, "secret\n")
	if err := os.Symlink(outside, filepath.Join(dir, "audit.2.jsonl")); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "audit.3.jsonl"), 0o700); err != nil {
		t.Fatal(err)
	}
	s := newService("http://127.0.0.1:8123", viewerToken)
	s.op = newOperator(map[string]bool{"operator.noop": true})
	families, _ := parseLogFamilies("dashboard.audit")
	logs, err := newLogs(root, families)
	if err != nil {
		t.Fatal(err)
	}
	s.logs = logs
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"operator.noop"}}
	h.Logs = &logsCaps{Version: 1, Families: []string{"dashboard.audit"}}
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	return &logsFixture{t: t, s: s, c: login(t, s), root: root, audit: audit}
}

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

// answer replies to the next logAccess frame the way 4D does, and returns the frame.
func (f *logsFixture) answer(ok bool, code string) chan map[string]any {
	seen := make(chan map[string]any, 1)
	go func() {
		v := <-f.s.out
		body, _ := json.Marshal(v)
		var m map[string]any
		_ = json.Unmarshal(body, &m)
		seen <- m
		if code == "silent" {
			return
		}
		f.s.mu.Lock()
		seq := f.s.current.Seq + 1
		f.s.mu.Unlock()
		r := frame("logAccessResult", seq)
		r.ID, r.OK, r.Error = m["id"].(string), &ok, code
		if err := f.s.apply(r); err != nil {
			f.t.Error(err)
		}
	}()
	return seen
}

func (f *logsFixture) files() []map[string]any {
	w := f.c.call("GET", "logs/files", "")
	if w.Code != 200 {
		f.t.Fatal(w.Code, w.Body)
	}
	var body struct{ Files []map[string]any }
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return body.Files
}

func (f *logsFixture) fileID(name string) string {
	for _, file := range f.files() {
		if file["name"] == name {
			return file["id"].(string)
		}
	}
	f.t.Fatal("no file", name)
	return ""
}

func (f *logsFixture) open(name string) map[string]any {
	f.t.Helper()
	f.answer(true, "")
	w := f.c.call("POST", "logs/open", `{"file":"`+f.fileID(name)+`"}`)
	if w.Code != 200 {
		f.t.Fatal(w.Code, w.Body)
	}
	return decode(f.t, w)
}

func (f *logsFixture) page(view, cursor, direction string, limit int) (int, map[string]any) {
	q := url.Values{"view": {view}, "cursor": {cursor}, "direction": {direction}, "limit": {fmt.Sprint(limit)}}
	w := f.c.call("GET", "logs/page?"+q.Encode(), "")
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return w.Code, body
}

func texts(page map[string]any) []string {
	var out []string
	for _, l := range page["lines"].([]any) {
		out = append(out, l.(map[string]any)["text"].(string))
	}
	return out
}

func TestLogCatalogAndRoot(t *testing.T) {
	diag := logFamilies["4d.diagnostic"]
	if len(logFamilies) != 2 || logFamilies["dashboard.audit"].Dir != "dashboard" || diag == nil || diag.Sensitivity != "sensitive" || diag.Parse != "diagnostic" {
		t.Fatal(logFamilies)
	}
	for name, want := range map[string]bool{"4DDiagnosticLog.txt": true, "4DDiagnosticLog_1.txt": true, "4DDiagnosticLogTool_12.txt": true,
		"4DDiagnosticLogServer.txt": true, "4DDiagnosticLog.txt.bak": false, "4DDiagnosticLogX_1.txt": false, "x4DDiagnosticLog.txt": false,
		"4DDebugLog.txt": false, "Logweb.txt": false, "4DDiagnosticLog_1.txt\n": false} {
		if diag.re.MatchString(name) != want {
			t.Fatal(name, want)
		}
	}
	if _, err := parseLogCatalog([]byte(`{"version":1,"families":[{"id":"x","dir":"","pattern":"^a$","format":"text","sensitivity":"normal","parse":"regex"}]}`)); err == nil {
		t.Fatal("an unknown parser was accepted")
	}
	for _, bad := range []string{
		`{"version":1,"families":[{"id":"x","dir":"..","pattern":"^a$","format":"text","sensitivity":"normal"}]}`,
		`{"version":1,"families":[{"id":"x","dir":"","pattern":"a","format":"text","sensitivity":"normal"}]}`,
		`{"version":1,"families":[{"id":"x","dir":"","pattern":"^a$","format":"html","sensitivity":"normal"}]}`,
		`{"version":1,"families":[{"id":"x","dir":"","pattern":"^a$","format":"text","sensitivity":"public"}]}`,
		`{"version":1,"families":[{"id":"x","dir":"a/b","pattern":"^a$","format":"text","sensitivity":"normal"}]}`,
	} {
		if _, err := parseLogCatalog([]byte(bad)); err == nil {
			t.Fatal(bad)
		}
	}
	if _, err := parseLogFamilies("4d.httpDebug"); err == nil {
		t.Fatal("a non-catalog family was accepted")
	}
	root := t.TempDir()
	link := filepath.Join(t.TempDir(), "link")
	_ = os.Symlink(root, link)
	for name, path := range map[string]string{"relative": "Logs", "missing": filepath.Join(root, "none"), "symlink": link} {
		if _, err := newLogs(path, logFamilies); err == nil {
			t.Fatal(name)
		}
	}
}

func TestLogFileMapIsConfined(t *testing.T) {
	f := newLogsFixture(t)
	files := f.files()
	var names []string
	for _, file := range files {
		names = append(names, file["name"].(string))
		if len(file) != 5 || strings.Contains(fmt.Sprint(file), f.root) {
			t.Fatal("file map leaks a path or extra field", file)
		}
	}
	if fmt.Sprint(names) != "[audit.1.jsonl audit.jsonl]" && fmt.Sprint(names) != "[audit.jsonl audit.1.jsonl]" {
		t.Fatal("only regular catalog files are listed", names)
	}
	// Viewer cookie alone, logs off, or a plain-HTTP LAN origin get nothing.
	if w := (&client{s: f.s}).call("GET", "logs/files", ""); w.Code != 401 {
		t.Fatal("viewer-only", w.Code)
	}
	f.s.logs = nil
	if w := f.c.call("GET", "logs/files", ""); w.Code != 404 {
		t.Fatal("logs disabled", w.Code)
	}
}

func TestLogOpenIsAuthorizedAndAuditedFirst(t *testing.T) {
	f := newLogsFixture(t)
	id := f.fileID("audit.jsonl")
	seen := f.answer(true, "")
	w := f.c.call("POST", "logs/open", `{"file":"`+id+`"}`)
	frameSeen := <-seen
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	if frameSeen["kind"] != "logAccess" || frameSeen["op"] != "open" || frameSeen["family"] != "dashboard.audit" ||
		frameSeen["file"] != "audit.jsonl" || frameSeen["actor"] != actorOf(f.c.operator) || len(frameSeen) != 8 {
		t.Fatal(frameSeen)
	}
	body := decode(t, w)
	lines := texts(body["page"].(map[string]any))
	if len(lines) != defaultTailLines || lines[len(lines)-1] != `{"v":1,"n":150}` || lines[0] != `{"v":1,"n":51}` {
		t.Fatal("tail", len(lines), lines[0], lines[len(lines)-1])
	}
	// Denied and timed-out opens serve nothing.
	f.answer(false, "host_denied")
	if w := f.c.call("POST", "logs/open", `{"file":"`+id+`"}`); w.Code != 403 || decode(t, w)["error"] != "host_denied" {
		t.Fatal("denied", w.Code)
	}
	logAccessTimeout = 100 * time.Millisecond
	defer func() { logAccessTimeout = 5 * time.Second }()
	pending := f.answer(false, "silent")
	if w := f.c.call("POST", "logs/open", `{"file":"`+id+`"}`); w.Code != 504 {
		t.Fatal("timeout", w.Code)
	}
	late := frame("logAccessResult", f.s.current.Seq+1)
	ok := true
	late.ID, late.OK = (<-pending)["id"].(string), &ok
	if err := f.s.apply(late); err != nil {
		t.Fatal("a late result must be dropped, not fatal", err)
	}
	if err := f.s.apply(frameWithID("logAccessResult", f.s.current.Seq+1, strings.Repeat("e", 64))); err == nil {
		t.Fatal("uncorrelated logAccessResult accepted")
	}
	if w := f.c.call("POST", "logs/open", `{"file":"`+strings.Repeat("0", 32)+`"}`); w.Code != 404 {
		t.Fatal("unknown file id", w.Code)
	}
	if w := f.c.call("POST", "logs/open", `{"file":"../../etc/passwd"}`); w.Code != 404 {
		t.Fatal("path as id", w.Code)
	}
}

func frameWithID(kind string, seq uint64, id string) message {
	m := frame(kind, seq)
	ok := true
	m.ID, m.OK = id, &ok
	return m
}

func TestWaitingForFourDDoesNotHoldTheLock(t *testing.T) {
	f := newLogsFixture(t)
	id := f.fileID("audit.jsonl")
	pending := f.answer(false, "silent")
	done := make(chan int, 1)
	go func() { done <- f.c.call("POST", "logs/open", `{"file":"`+id+`"}`).Code }()
	<-pending
	start := time.Now()
	if w := f.c.call("GET", "status", ""); w.Code != 200 || time.Since(start) > time.Second {
		t.Fatal("status blocked while an open waits for 4D")
	}
	if w := f.c.call("POST", "logs/open", `{"file":"`+id+`"}`); w.Code != 429 {
		t.Fatal("second open while one is pending", w.Code)
	}
	if code := <-done; code != 504 {
		t.Fatal(code)
	}
}

func TestLogPagingTailAndCursors(t *testing.T) {
	f := newLogsFixture(t)
	opened := f.open("audit.jsonl")
	view, page := opened["view"].(string), opened["page"].(map[string]any)
	code, older := f.page(view, page["before"].(string), "backward", 500)
	if code != 200 || len(texts(older)) != 50 || texts(older)[0] != `{"v":1,"n":1}` || older["atStart"] != true {
		t.Fatal(code, len(texts(older)))
	}
	// Follow: complete the partial line and append more; forward from "after" returns them.
	fh, _ := os.OpenFile(f.audit, os.O_APPEND|os.O_WRONLY, 0)
	_, _ = fh.WriteString("\n" + `{"v":1,"n":151}` + "\n" + `{"v":1,"n":152}`)
	fh.Close()
	code, newer := f.page(view, page["after"].(string), "forward", 500)
	if code != 200 || fmt.Sprint(texts(newer)) != `[{"v":1,"partial":true} {"v":1,"n":151}]` {
		t.Fatal(code, texts(newer))
	}
	// Tampered, foreign or malformed cursors are refused.
	cursor := page["before"].(string)
	for name, q := range map[string][4]string{
		"tampered": {view, "1" + cursor, "backward", "10"},
		"no mac":   {view, "0", "forward", "10"},
		"limit":    {view, cursor, "forward", "501"},
		"dir":      {view, cursor, "sideways", "10"},
	} {
		w := f.c.call("GET", "logs/page?"+url.Values{"view": {q[0]}, "cursor": {q[1]}, "direction": {q[2]}, "limit": {q[3]}}.Encode(), "")
		if w.Code != 400 {
			t.Fatal(name, w.Code)
		}
	}
	other := f.open("audit.1.jsonl")
	if code, _ := f.page(other["view"].(string), cursor, "backward", 10); code != 400 {
		t.Fatal("a cursor from another view was accepted", code)
	}
	if code, _ := f.page(view, cursor, "backward", 10); code != 404 {
		t.Fatal("a replaced view still answered", code)
	}
}

func TestLogRotationTruncationAndSwap(t *testing.T) {
	for name, change := range map[string]func(f *logsFixture){
		"rotated": func(f *logsFixture) {
			_ = os.Rename(f.audit, filepath.Join(filepath.Dir(f.audit), "audit.1.jsonl"))
			write(f.t, f.audit, "new\n")
		},
		"truncated": func(f *logsFixture) { _ = os.Truncate(f.audit, 0) },
		"symlink swap": func(f *logsFixture) {
			outside := filepath.Join(f.t.TempDir(), "x")
			write(f.t, outside, "secret\n")
			_ = os.Remove(f.audit)
			_ = os.Symlink(outside, f.audit)
		},
	} {
		f := newLogsFixture(t)
		opened := f.open("audit.jsonl")
		view, page := opened["view"].(string), opened["page"].(map[string]any)
		change(f)
		code, body := f.page(view, page["before"].(string), "backward", 10)
		want := map[string]string{"rotated": errRotated, "truncated": errTruncated, "symlink swap": errRotated}[name]
		if code != 410 || body["error"] != want {
			t.Fatal(name, code, body)
		}
	}
}

func TestLogLineHandling(t *testing.T) {
	f := newLogsFixture(t)
	long := strings.Repeat("x", maxLineBytes+10)
	huge := strings.Repeat("y", maxPageBytes+10)
	write(t, f.audit, "a\r\n"+string([]byte{0xff, 'b'})+"\n"+long+"\n"+huge+"\nz\n")
	opened := f.open("audit.jsonl")
	lines := opened["page"].(map[string]any)["lines"].([]any)
	if len(lines) != 5 {
		t.Fatal(len(lines))
	}
	get := func(i int) map[string]any { return lines[i].(map[string]any) }
	if get(0)["text"] != "a" || get(1)["text"] != "�b" || len(get(2)["text"].(string)) != maxLineBytes || get(2)["truncated"] != true ||
		get(3)["truncated"] != true || get(4)["text"] != "z" {
		t.Fatal(get(0), get(1), get(2)["truncated"], get(3)["truncated"], get(4))
	}
}

func TestLogFramesAreNegotiatedAndScoped(t *testing.T) {
	s := newService("http://127.0.0.1:8123", viewerToken)
	h := frame("hello", 1)
	h.Logs = &logsCaps{Version: 1, Families: []string{"dashboard.audit"}}
	if s.apply(h) == nil {
		t.Fatal("hello declared logs the CLI did not enable")
	}
	f := newLogsFixture(t)
	m := frame("snapshot", f.s.current.Seq+1)
	m.Logs = &logsCaps{Version: 1}
	if f.s.apply(m) == nil {
		t.Fatal("logs outside hello")
	}
	for _, caps := range []*logsCaps{nil, {Version: 2, Families: []string{"dashboard.audit"}}, {Version: 1}} {
		s := newService("http://127.0.0.1:8123", viewerToken)
		s.op = newOperator(map[string]bool{"operator.noop": true})
		s.logs = f.s.logs
		h := frame("hello", 1)
		h.Operator = &operatorCaps{Version: 1, Actions: []string{"operator.noop"}}
		h.Logs = caps
		if s.apply(h) == nil {
			t.Fatal("mismatched logs negotiation", caps)
		}
	}
	_ = http.StatusOK
}

func TestLogsNeedTLSOrLoopback(t *testing.T) {
	f := newLogsFixture(t)
	s := newService("http://192.0.2.10:8123", viewerToken)
	s.op, s.logs = newOperator(map[string]bool{"operator.noop": true}), f.s.logs
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"operator.noop"}}
	h.Logs = &logsCaps{Version: 1, Families: []string{"dashboard.audit"}}
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	c := loginAt(t, s, "192.0.2.10:8123")
	if w := c.call("GET", "logs/files", "", hostIs("192.0.2.10:8123")); w.Code != 403 || decode(t, w)["error"] != "transport_not_allowed" {
		t.Fatal("plain-HTTP LAN log access", w.Code)
	}
}

// diagnosticFixture builds a 4D-style diagnostic log: seq time [component] LEVEL - message, one line per
// minute from 2026-11-15T10:00, with a mix of levels, multibyte text, a continuation line and an unparsable banner.
func diagnosticText(n int) string {
	levels := []string{"INFO", "ERROR", "WARN", "DEBUG"}
	var b strings.Builder
	b.WriteString("-- startup banner without a timestamp --\n")
	start := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)
	for i := 0; i < n; i++ {
		at := start.Add(time.Duration(i) * time.Minute).Format("2006-01-02T15:04:05.000")
		fmt.Fprintf(&b, "%d %s [tool4d.APPL] %s - message %d 日本語\n", i+1, at, levels[i%len(levels)], i)
		if i%50 == 7 {
			b.WriteString("    continuation line of the previous message\n")
		}
	}
	return b.String()
}

type diagFixture struct {
	*logsFixture
	view string
}

func newDiagFixture(t *testing.T, text string) *diagFixture {
	t.Helper()
	f := newLogsFixture(t)
	families, _ := parseLogFamilies("dashboard.audit,4d.diagnostic")
	f.s.logs.families = families
	write(t, filepath.Join(f.root, "4DDiagnosticLogTool_1.txt"), text)
	opened := f.open("4DDiagnosticLogTool_1.txt")
	return &diagFixture{f, opened["view"].(string)}
}

func (d *diagFixture) get(q url.Values) (int, map[string]any) {
	q.Set("view", d.view)
	w := d.c.call("GET", "logs/page?"+q.Encode(), "")
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return w.Code, body
}

func TestDiagnosticLineParsing(t *testing.T) {
	stamp, level, ok := parseDiagnostic("33 2026-11-15T11:57:46.101 [tool4d.APPL] ERROR - dashboard probe message one ()")
	if !ok || stamp != "2026-11-15T11:57:46.101" || level != "ERROR" {
		t.Fatal(stamp, level, ok)
	}
	if s, _, ok := parseDiagnostic("5 2026-11-15T11:57:46 [a b] INFO - x"); !ok || s != "2026-11-15T11:57:46.000" {
		t.Fatal("a missing fraction is padded", s, ok)
	}
	if s, _, _ := parseDiagnostic("5 2026-11-15T11:57:46.5 [a] INFO - x"); s != "2026-11-15T11:57:46.500" {
		t.Fatal("a short fraction is padded to the right", s)
	}
	for _, bad := range []string{"", "    continuation", "-- banner --", "5 2026-13-15T11:57:46.101 [a] INFO - x",
		"5 2026-11-15T25:57:46.101 [a] INFO - x", "x 2026-11-15T11:57:46.101 [a] INFO - x", "5 2026-11-15T11:57:46.101 [a] info - x",
		"5 2026-11-15T11:57:46.101 [a] INFO x", "5 2026-11-15T11:57:46.101 INFO - x"} {
		if _, _, ok := parseDiagnostic(bad); ok {
			t.Fatalf("%q parsed", bad)
		}
	}
	for in, want := range map[string]string{"2026-11-15T10:30": "2026-11-15T10:30:00.000", "2026-11-15T10:30:15": "2026-11-15T10:30:15.000",
		"2026-11-15T10:30:15.2": "2026-11-15T10:30:15.200", "2026-11-15T10:30:15.25": "2026-11-15T10:30:15.250"} {
		if got, ok := normalizeStamp(in); !ok || got != want {
			t.Fatal(in, got, ok)
		}
	}
	if _, ok := normalizeStamp("2026-02-30T10:00"); ok {
		t.Fatal("an impossible date was accepted")
	}
}

func TestDiagnosticFilesAdvertiseFilters(t *testing.T) {
	d := newDiagFixture(t, diagnosticText(10))
	for _, file := range d.files() {
		filters, has := file["filters"]
		if (file["family"] == "4d.diagnostic") != has || (has && fmt.Sprint(filters) != "[level time]") {
			t.Fatal(file)
		}
	}
}

func TestDiagnosticLevelFilterForwardAndBackward(t *testing.T) {
	d := newDiagFixture(t, diagnosticText(400))
	code, all := d.get(url.Values{"cursor": {d.firstCursor(t)}, "direction": {"forward"}, "limit": {"500"}, "level": {"ERROR"}})
	if code != 200 {
		t.Fatal(code, all)
	}
	got := texts(all)
	if len(got) != 100 || all["limited"] != false || all["atEnd"] != true {
		t.Fatal("forward filter", len(got), all["limited"], all["atEnd"])
	}
	for _, line := range got {
		if !strings.Contains(line, "] ERROR - ") {
			t.Fatal(line)
		}
	}
	// Paging with a small limit continues exactly where it stopped, with no gaps or repeats.
	var seen []string
	cursor := d.firstCursor(t)
	for i := 0; i < 20 && len(seen) < 100; i++ {
		_, page := d.get(url.Values{"cursor": {cursor}, "direction": {"forward"}, "limit": {"30"}, "level": {"ERROR"}})
		seen = append(seen, texts(page)...)
		cursor = page["after"].(string)
	}
	if fmt.Sprint(seen) != fmt.Sprint(got) {
		t.Fatal("paged filter differs", len(seen))
	}
	// Backward from the end returns the newest matches, oldest first.
	_, end := d.get(url.Values{"cursor": {all["after"].(string)}, "direction": {"backward"}, "limit": {"5"}, "level": {"WARN"}})
	back := texts(end)
	if len(back) != 5 || !strings.Contains(back[4], "message 398 ") || !strings.Contains(back[0], "message 382 ") || end["atStart"] != false {
		t.Fatal("backward", back)
	}
	// Walking backward to the start sees every WARN once.
	var walked []string
	cursor = all["after"].(string)
	for i := 0; i < 40; i++ {
		_, page := d.get(url.Values{"cursor": {cursor}, "direction": {"backward"}, "limit": {"7"}, "level": {"WARN"}})
		walked = append(append([]string{}, texts(page)...), walked...)
		cursor = page["before"].(string)
		if page["atStart"] == true {
			break
		}
	}
	if len(walked) != 100 {
		t.Fatal("walked", len(walked))
	}
	// Continuation lines and the banner never match a level.
	for _, line := range walked {
		if !strings.Contains(line, "] WARN - ") {
			t.Fatal(line)
		}
	}
}

// firstCursor is a signed cursor for the start of the file, obtained the way the browser does: by paging
// backward from the opened tail until the start is reached.
func (d *diagFixture) firstCursor(t *testing.T) string {
	t.Helper()
	_, page := d.get(url.Values{"time": {"2000-01-01T00:00"}, "limit": {"1"}})
	return page["before"].(string)
}

func TestDiagnosticFilterAndTimeAreValidated(t *testing.T) {
	d := newDiagFixture(t, diagnosticText(20))
	cursor := d.firstCursor(t)
	base := func(extra url.Values) url.Values {
		q := url.Values{"cursor": {cursor}, "direction": {"forward"}, "limit": {"10"}}
		for k, v := range extra {
			q[k] = v
		}
		return q
	}
	for name, q := range map[string]url.Values{
		"unknown level":   base(url.Values{"level": {"error"}}),
		"expression":      base(url.Values{"level": {"ERROR|INFO"}}),
		"empty level":     base(url.Values{"level": {""}}),
		"unknown key":     base(url.Values{"regex": {"x"}}),
		"time and cursor": base(url.Values{"time": {"2026-11-15T10:00"}}),
		"bad time":        {"time": {"yesterday"}, "limit": {"10"}},
		"impossible time": {"time": {"2026-02-30T10:00"}, "limit": {"10"}},
		"zone suffix":     {"time": {"2026-11-15T10:00:00Z"}, "limit": {"10"}},
		"time backward":   {"time": {"2026-11-15T10:00"}, "direction": {"backward"}, "limit": {"10"}},
		"no cursor":       {"direction": {"forward"}, "limit": {"10"}},
		"no direction":    {"cursor": {cursor}, "limit": {"10"}},
	} {
		if code, body := d.get(q); code != 400 {
			t.Fatal(name, code, body)
		}
	}
	// The audit family has no parsed columns, so filters are refused there rather than ignored.
	audit := newLogsFixture(t)
	opened := audit.open("audit.jsonl")
	q := url.Values{"view": {opened["view"].(string)}, "cursor": {opened["page"].(map[string]any)["before"].(string)},
		"direction": {"backward"}, "limit": {"10"}, "level": {"ERROR"}}
	if w := audit.c.call("GET", "logs/page?"+q.Encode(), ""); w.Code != 400 || decode(t, w)["error"] != "unsupported_filter" {
		t.Fatal("level on a family without a parser", w.Code)
	}
	q = url.Values{"view": {opened["view"].(string)}, "time": {"2026-11-15T10:00"}, "limit": {"10"}}
	if w := audit.c.call("GET", "logs/page?"+q.Encode(), ""); w.Code != 400 {
		t.Fatal("time on a family without a parser", w.Code)
	}
}

func TestDiagnosticJumpToTime(t *testing.T) {
	text := diagnosticText(3000)
	d := newDiagFixture(t, text)
	first := func(target string) (string, map[string]any) {
		code, page := d.get(url.Values{"time": {target}, "limit": {"3"}})
		if code != 200 {
			t.Fatal(target, code, page)
		}
		lines := texts(page)
		if len(lines) == 0 {
			return "", page
		}
		return lines[0], page
	}
	// 1500 minutes after 10:00 is 11:00 the next day: message 1500, exactly.
	line, page := first("2026-11-16T11:00")
	if !strings.Contains(line, "2026-11-16T11:00:00.000") || !strings.Contains(line, "message 1500 ") || page["atTime"] != true {
		t.Fatal(line)
	}
	// Between two lines: the next line at or after the time.
	if line, _ := first("2026-11-16T11:00:30"); !strings.Contains(line, "message 1501 ") {
		t.Fatal(line)
	}
	// Before the first line: the first timestamped line (the banner has no timestamp, so a jump skips it).
	if line, page := first("2000-01-01T00:00"); !strings.Contains(line, "message 0 ") || page["atStart"] != false {
		t.Fatal(line, page["atStart"])
	}
	// After the last line: nothing at or after, and the page says so.
	if line, page := first("2099-01-01T00:00"); line != "" || page["atTime"] != false || page["atEnd"] != true {
		t.Fatal("past the end", line, page["atEnd"])
	}
	// Every minute in a sample resolves to its own line (binary search against a linear reference).
	for _, i := range []int{0, 1, 2, 63, 64, 999, 1234, 2998, 2999} {
		at := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC).Add(time.Duration(i) * time.Minute).Format("2006-01-02T15:04")
		if line, _ := first(at); !strings.Contains(line, fmt.Sprintf("message %d ", i)) {
			t.Fatal(i, line)
		}
	}
	// A jump combined with a level filter returns matches from that point only.
	code, page := d.get(url.Values{"time": {"2026-11-16T11:00"}, "limit": {"2"}, "level": {"ERROR"}})
	lines := texts(page)
	if code != 200 || len(lines) != 2 || !strings.Contains(lines[0], "message 1501 ") || !strings.Contains(lines[1], "message 1505 ") {
		t.Fatal(code, lines)
	}
}

func TestDiagnosticScansAreBounded(t *testing.T) {
	// 20 MiB of INFO lines with a single ERROR at the very end: one request must stop at the scan budget and
	// say so, and following its continuation cursor must reach the match.
	var b strings.Builder
	start := time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)
	line := func(i int, level string) string {
		return fmt.Sprintf("%d %s [x] %s - %s\n", i, start.Add(time.Duration(i)*time.Millisecond).Format("2006-01-02T15:04:05.000"), level, strings.Repeat("p", 200))
	}
	n := (20 << 20) / 260
	for i := 0; i < n; i++ {
		b.WriteString(line(i, "INFO"))
	}
	b.WriteString(line(n, "ERROR"))
	d := newDiagFixture(t, b.String())
	cursor := d.firstCursor(t)
	hits, hops := 0, 0
	for ; hops < 10; hops++ {
		code, page := d.get(url.Values{"cursor": {cursor}, "direction": {"forward"}, "limit": {"5"}, "level": {"ERROR"}})
		if code != 200 {
			t.Fatal(code, page)
		}
		hits += len(texts(page))
		if hops == 0 && (page["limited"] != true || len(texts(page)) != 0) {
			t.Fatal("the first request must stop at the scan budget", page["limited"])
		}
		cursor = page["after"].(string)
		if page["atEnd"] == true {
			break
		}
	}
	if hits != 1 || hops < 2 || hops > 4 {
		t.Fatal("hits", hits, "hops", hops)
	}
	// Backward from the end with no match in the budget also stops and continues.
	code, page := d.get(url.Values{"cursor": {cursor}, "direction": {"backward"}, "limit": {"5"}, "level": {"TRACE"}})
	if code != 200 || page["limited"] != true || len(texts(page)) != 0 || page["atStart"] == true {
		t.Fatal("backward budget", code, page["limited"])
	}
}

func TestDiagnosticMultibyteAndLongLines(t *testing.T) {
	long := "9 2026-11-15T10:00:09.000 [x] ERROR - " + strings.Repeat("あ", 10000) + "\n"
	text := "1 2026-11-15T10:00:01.000 [x] ERROR - 日本語のメッセージ\n" + long + "2 2026-11-15T10:00:10.000 [x] ERROR - after\n"
	d := newDiagFixture(t, text)
	_, page := d.get(url.Values{"cursor": {d.firstCursor(t)}, "direction": {"forward"}, "limit": {"10"}, "level": {"ERROR"}})
	got := page["lines"].([]any)
	if len(got) != 3 || !strings.Contains(got[0].(map[string]any)["text"].(string), "日本語のメッセージ") ||
		got[1].(map[string]any)["truncated"] != true || got[2].(map[string]any)["text"] != "2 2026-11-15T10:00:10.000 [x] ERROR - after" {
		t.Fatal(len(got))
	}
}
