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
	if len(logFamilies) != 1 || logFamilies["dashboard.audit"].Dir != "dashboard" {
		t.Fatal(logFamilies)
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
