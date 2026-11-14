package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func frame(kind string, seq uint64) message {
	return message{Protocol: 1, Kind: kind, Epoch: "test-epoch", Seq: seq, SampledAt: time.Now().UTC().Format(time.RFC3339Nano)}
}

func hello(t *testing.T, s *service) {
	t.Helper()
	if err := s.apply(frame("hello", 1)); err != nil {
		t.Fatal(err)
	}
}

func TestFramesAndState(t *testing.T) {
	s := newService("http://127.0.0.1:8080", "token")
	h := frame("hello", 1)
	m := frame("snapshot", 2)
	m.Metrics = []metric{{ID: "cpu", Label: "CPU", Type: "number", Unit: "%", Kind: "gauge", Availability: "available", Value: float64(0)}}
	m.Processes = []entity{{ID: "process:1", State: "executing", Type: "worker"}}
	var b bytes.Buffer
	for _, value := range []message{h, m} {
		if err := json.NewEncoder(&b).Encode(value); err != nil {
			t.Fatal(err)
		}
	}
	// A byte-at-a-time reader models arbitrary pipe chunk boundaries.
	if err := s.read(&singleByteReader{b.Bytes()}); err != nil {
		t.Fatal(err)
	}
	if s.current.Metrics["cpu"].Value != float64(0) || len(s.current.Processes) != 1 {
		t.Fatal(s.current)
	}
	update := frame("update", 3)
	update.Delete = &deletions{Metrics: []string{"cpu"}, Processes: []string{"process:1"}}
	if err := s.apply(update); err != nil {
		t.Fatal(err)
	}
	if len(s.current.Processes) != 0 || len(s.current.Metrics) != 0 || len(s.current.History) != 0 {
		t.Fatal(s.current)
	}
	if err := s.apply(update); err == nil {
		t.Fatal("accepted replay")
	}
}

type singleByteReader struct{ bytes []byte }

func (r *singleByteReader) Read(b []byte) (int, error) {
	if len(r.bytes) == 0 {
		return 0, io.EOF
	}
	b[0] = r.bytes[0]
	r.bytes = r.bytes[1:]
	return 1, nil
}

func TestInvalidFrames(t *testing.T) {
	for _, raw := range []string{
		`{"protocol":2}`, `{"protocol":1} {}`, `[]`, "null", "{\"kind\":\"\xff\"}",
		strings.Repeat("x", maxFrame+1), `{"protocol":1,"unexpected":true}`,
	} {
		s := newService("http://127.0.0.1", "token")
		if err := s.read(strings.NewReader(raw + "\n")); err == nil {
			t.Fatalf("accepted %q", raw[:min(len(raw), 80)])
		}
	}
	s := newService("http://127.0.0.1", "token")
	hello(t, s)
	m := frame("snapshot", 2)
	m.Metrics = []metric{{ID: "missing", Label: "Missing", Type: "number", Kind: "gauge", Availability: "missing", Value: float64(0)}}
	if err := s.apply(m); err == nil {
		t.Fatal("unavailable became zero")
	}
	if s.current.Seq != 1 {
		t.Fatal("invalid update mutated state")
	}
	m.Metrics[0].Value = nil
	m.Metrics[0].Reason = "not provided"
	if err := s.apply(m); err != nil {
		t.Fatal(err)
	}
}

func TestRecordCountsAreWholeNonnegativeSafeIntegers(t *testing.T) {
	for _, test := range []struct {
		value float64
		valid bool
	}{{0, true}, {3, true}, {0.3, false}, {-1, false}, {9007199254740991, true}, {9007199254740992, false}} {
		t.Run(fmt.Sprint(test.value), func(t *testing.T) {
			s := newService("http://127.0.0.1", "token")
			hello(t, s)
			sample := frame("snapshot", 2)
			sample.Metrics = []metric{{ID: "license.usage.records", Label: "Retained license records", Type: "number", Unit: "records", Kind: "gauge", Availability: "available", Value: test.value}}
			err := s.apply(sample)
			if (err == nil) != test.valid {
				t.Fatalf("record count %v: %v", test.value, err)
			}
			if !test.valid && s.current.Seq != 1 {
				t.Fatal("invalid record count mutated state")
			}
		})
	}
}

func TestBackupMetadataContractAndNoRepeatedValueHistory(t *testing.T) {
	for _, test := range []struct {
		id, kind, unit string
		value          any
		valid          bool
	}{
		{"backup.statusCode", "number", "", float64(37), true},
		{"backup.statusCode", "number", "", float64(-1), true},
		{"backup.statusCode", "number", "", float64(1.5), false},
		{"backup.duration", "number", "ms", float64(0), true},
		{"backup.duration", "number", "ms", float64(1200), true},
		{"backup.duration", "number", "s", float64(1200), false},
		{"backup.duration", "number", "ms", float64(-1), false},
		{"backup.duration", "number", "ms", float64(2147483648), false},
		{"backup.lastAt", "text", "", "2026-11-14T00:00:00", true},
		{"backup.nextAt", "text", "", "2026-11-15T00:00:00Z", false},
		{"backup.lastAt", "text", "", "0000-00-00T00:00:00", false},
		{"backup.beginUTC", "text", "", "2026-11-13T15:00:00.123Z", true},
		{"backup.beginUTC", "text", "", "2026-02-31T15:00:00.123Z", false},
		{"backup.beginUTC", "text", "", "2026-11-13T15:00:00Z", false},
		{"backup.beginUTC", "text", "", "/private/backup", false},
		{"backup.statusText", "text", "", "private status", false},
	} {
		t.Run(fmt.Sprint(test.id, test.value), func(t *testing.T) {
			s := newService("http://127.0.0.1", "token")
			hello(t, s)
			sample := frame("snapshot", 2)
			sample.Metrics = []metric{{ID: test.id, Label: "Backup", Type: test.kind, Unit: test.unit,
				Kind: "static", Availability: "available", Value: test.value}}
			err := s.apply(sample)
			if (err == nil) != test.valid {
				t.Fatalf("backup metadata: %v", err)
			}
			if !test.valid && s.current.Seq != 1 {
				t.Fatal("invalid metadata mutated state")
			}
			if test.valid {
				sample.Seq++
				if err := s.apply(sample); err != nil || len(s.current.History) != 0 {
					t.Fatal("cached metadata acquired a rate graph", err)
				}
			}
		})
	}
}

func TestBoundedHistoryAndCoalescing(t *testing.T) {
	s := newService("http://127.0.0.1", "token")
	hello(t, s)
	client := make(chan []byte, 1)
	s.clients[client] = true
	for i := uint64(2); i < 202; i++ {
		m := frame("snapshot", i)
		m.Metrics = []metric{{ID: "cpu", Label: "CPU", Type: "number", Kind: "gauge", Availability: "available", Value: float64(i)}}
		if err := s.apply(m); err != nil {
			t.Fatal(err)
		}
	}
	if len(s.current.History["cpu"]) != 60 || len(s.current.Activity) != 60 || len(client) != 1 {
		t.Fatal("unbounded history or queue")
	}
	var current state
	if err := json.Unmarshal(<-client, &current); err != nil || current.Seq != 201 {
		t.Fatal(current, err)
	}
	s.last = time.Now().Add(-16 * time.Second)
	s.expire()
	if s.current.Status != "stale" {
		t.Fatal("not stale")
	}
}

func TestStaticDatastoreCountsAreBoundedAndUnavailableIsNotZero(t *testing.T) {
	for _, test := range []struct {
		value float64
		valid bool
	}{{0, true}, {512, true}, {513, false}, {-1, false}, {1.5, false}} {
		m := metric{ID: "datastore.classes", Label: "Mapped dataclasses", Type: "number", Unit: "dataclasses", Kind: "static", Availability: "available", Value: test.value}
		if validMetric(m) != test.valid {
			t.Fatalf("dataclass count %v", test.value)
		}
	}
	s := newService("http://127.0.0.1", "token")
	hello(t, s)
	sample := frame("snapshot", 2)
	sample.Metrics = []metric{
		{ID: "datastore.type", Label: "Host datastore type", Type: "text", Kind: "static", Availability: "available", Value: "4D"},
		{ID: "datastore.networked", Label: "Host datastore networked", Type: "boolean", Kind: "static", Availability: "available", Value: false},
		{ID: "datastore.classes", Label: "Mapped dataclasses", Type: "number", Unit: "dataclasses", Kind: "static", Availability: "unsupported", Reason: "No datastore"},
	}
	if err := s.apply(sample); err != nil {
		t.Fatal(err)
	}
	if len(s.current.History) != 0 || s.current.Metrics["datastore.classes"].Value != nil {
		t.Fatal("static metadata graphed or unavailable became zero")
	}
}

func TestEngineTableCountsAreBoundedAndFlagsAreStrictBooleans(t *testing.T) {
	for _, test := range []struct {
		value float64
		valid bool
	}{{0, true}, {512, true}, {513, false}, {-1, false}, {1.5, false}} {
		m := metric{ID: "datastore.encryptedTables", Label: "Encrypted tables", Type: "number", Unit: "tables", Kind: "static", Availability: "available", Value: test.value}
		if validMetric(m) != test.valid {
			t.Fatalf("table count %v", test.value)
		}
	}
	for _, test := range []struct {
		value any
		valid bool
	}{{true, true}, {false, true}, {"false", false}, {float64(0), false}, {nil, false}} {
		m := metric{ID: "datastore.locked", Label: "Datastore write freeze (lock, backup or VSS)", Type: "boolean", Kind: "gauge", Availability: "available", Value: test.value}
		if validMetric(m) != test.valid {
			t.Fatalf("lock flag %v", test.value)
		}
	}
	unavailable := metric{ID: "datastore.encryptionKeyProvided", Label: "Data encryption key provided", Type: "boolean", Kind: "static", Availability: "unsupported", Reason: "Data file is not encrypted; no data key applies"}
	if !validMetric(unavailable) {
		t.Fatal("not-applicable key state rejected")
	}
	unavailable.Value = false
	if validMetric(unavailable) {
		t.Fatal("unavailable key state carried a value")
	}
}

func TestRefreshCorrelation(t *testing.T) {
	s := newService("http://127.0.0.1", "token")
	hello(t, s)
	id, err := s.request()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.request(); err != errBusy {
		t.Fatal("duplicate refresh admitted")
	}
	m := frame("result", 2)
	ok := true
	m.ID, m.OK = "wrong", &ok
	if err := s.apply(m); err == nil {
		t.Fatal("uncorrelated result accepted")
	}
	m.ID = id
	if err := s.apply(m); err != nil {
		t.Fatal(err)
	}
	s.lastRequest = time.Time{}
	lateID, err := s.request()
	if err != nil {
		t.Fatal(err)
	}
	s.requestAt = time.Now().Add(-11 * time.Second)
	s.expire()
	if s.pending != "" {
		t.Fatal("request did not expire")
	}
	late := frame("result", 3)
	late.ID, late.OK = lateID, &ok
	if err := s.apply(late); err != nil {
		t.Fatalf("late result should be consumed, not crash: %v", err)
	}
	late.Seq = 4
	if err := s.apply(late); err == nil {
		t.Fatal("late result was replayed")
	}
}

func TestHistoryGapsAndActivitySnapshots(t *testing.T) {
	s := newService("http://127.0.0.1", "token")
	hello(t, s)
	cpu := 0.15
	sample := frame("snapshot", 2)
	sample.Metrics = []metric{
		{ID: "cpu", Label: "CPU", Type: "number", Kind: "gauge", Availability: "available", Value: float64(10)},
		{ID: "process.count", Label: "Processes", Type: "number", Kind: "gauge", Availability: "available", Value: float64(1)},
	}
	sample.Processes = []entity{{ID: "p:1", State: "executing", CPU: &cpu}}
	if err := s.apply(sample); err != nil {
		t.Fatal(err)
	}
	update := frame("update", 3)
	update.Metrics = []metric{{ID: "cpu", Label: "CPU", Type: "number", Kind: "gauge", Availability: "error", Reason: "Unavailable"}}
	update.Processes = []entity{{ID: "p:1", State: "waiting"}}
	if err := s.apply(update); err != nil {
		t.Fatal(err)
	}
	if len(s.current.History["cpu"]) != 2 || *s.current.History["cpu"][0].Value != 10 || s.current.History["cpu"][1].Value != nil {
		t.Fatal("unavailable sample erased history or became zero", s.current.History)
	}
	if s.current.Activity[0].Processes.Entities["p:1"].State != "executing" ||
		s.current.Activity[1].Processes.Entities["p:1"].State != "waiting" ||
		s.current.Activity[1].Processes.Entities["p:1"].CPU != nil {
		t.Fatal("activity did not preserve distinct snapshots")
	}
	update = frame("update", 4)
	update.Metrics = []metric{{ID: "process.count", Label: "Processes", Type: "number", Kind: "gauge", Availability: "available", Value: float64(0)}}
	update.Delete = &deletions{Processes: []string{"p:1"}}
	if err := s.apply(update); err != nil {
		t.Fatal(err)
	}
	if current := s.current.Activity[2].Processes.Entities; current == nil || len(current) != 0 {
		t.Fatal("known empty enumeration became unavailable")
	}
	update = frame("update", 5)
	update.Metrics = []metric{{ID: "process.count", Label: "Processes", Type: "number", Kind: "gauge", Availability: "error", Reason: "Enumeration failed"}}
	if err := s.apply(update); err != nil {
		t.Fatal(err)
	}
	if s.current.Activity[3].Processes.Entities != nil {
		t.Fatal("failed enumeration became zero")
	}
	id, err := s.request()
	if err != nil {
		t.Fatal(err)
	}
	result, ok := frame("result", 6), true
	result.ID, result.OK = id, &ok
	if err := s.apply(result); err != nil {
		t.Fatal(err)
	}
	if len(s.current.Activity) != 4 || len(s.current.History["cpu"]) != 2 {
		t.Fatal("action result duplicated history")
	}
	body, err := json.Marshal(s.current)
	if err != nil || !bytes.Contains(body, []byte(`"value":null`)) || !bytes.Contains(body, []byte(`"entities":null`)) {
		t.Fatal("SSE state does not preserve unavailable gaps", err)
	}
}

func TestIncompleteFrameAndOutputBackpressure(t *testing.T) {
	s := newService("http://127.0.0.1", "token")
	raw, _ := json.Marshal(frame("hello", 1))
	if err := s.read(bytes.NewReader(raw)); err == nil {
		t.Fatal("accepted unterminated frame")
	}
	for i := 0; i < cap(s.out); i++ {
		if err := s.emit(i); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.emit("overflow"); err == nil {
		t.Fatal("unbounded output")
	}
}

func TestAuthHostOriginAndReadOnlyRoutes(t *testing.T) {
	s := newService("http://127.0.0.1:8123", strings.Repeat("a", 64))
	hello(t, s)
	tests := []struct {
		method, path, host, origin, body string
		cookie                           bool
		status                           int
	}{
		{"GET", "/", "evil.example", "", "", false, 403},
		{"GET", "/api/events", "127.0.0.1:8123", "", "", false, 401},
		{"POST", "/api/session", "127.0.0.1:8123", "http://evil.example", s.token, false, 403},
		{"POST", "/api/session", "127.0.0.1:8123", s.origin, "wrong", false, 401},
		{"POST", "/api/session", "127.0.0.1:8123", s.origin, s.token, false, 204},
		{"POST", "/api/refresh", "127.0.0.1:8123", "", "", true, 403},
		{"POST", "/api/delete", "127.0.0.1:8123", s.origin, "", true, 404},
		{"POST", "/api/refresh", "127.0.0.1:8123", s.origin, "", true, 202},
		{"GET", "/app.js", "127.0.0.1:8123", "", "", false, 200},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprint(tt.method, tt.path, tt.status), func(t *testing.T) {
			r := httptest.NewRequest(tt.method, s.origin+tt.path, strings.NewReader(tt.body))
			r.Host = tt.host
			r.Header.Set("Origin", tt.origin)
			r.Header.Set("X-Dashboard-Action", "refresh")
			if tt.cookie {
				r.AddCookie(&http.Cookie{Name: "dashboard", Value: s.cookie})
			}
			w := httptest.NewRecorder()
			s.handler().ServeHTTP(w, r)
			if w.Code != tt.status {
				t.Fatalf("%d: %s", w.Code, w.Body)
			}
			if tt.path == "/api/session" && w.Code == 204 {
				cookie := w.Result().Cookies()[0]
				if !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode {
					t.Fatal(cookie)
				}
			}
		})
	}
}

func TestSSEInitialResnapshot(t *testing.T) {
	s := newService("http://placeholder", "token")
	hello(t, s)
	server := httptest.NewServer(s.handler())
	defer server.Close()
	s.origin = server.URL
	request, _ := http.NewRequest("GET", server.URL+"/api/events", nil)
	request.AddCookie(&http.Cookie{Name: "dashboard", Value: s.cookie})
	response, err := server.Client().Do(request)
	if err != nil {
		t.Fatal(err)
	}

	defer response.Body.Close()
	buffer := make([]byte, 2048)
	n, err := response.Body.Read(buffer)
	if err != nil || !bytes.Contains(buffer[:n], []byte(`"epoch":"test-epoch"`)) {
		t.Fatal(string(buffer[:n]), err)
	}
}

func TestCrossSiteNavigationDoesNotBlockPrivateURL(t *testing.T) {
	s := newService("http://127.0.0.1:8123", "token")
	for path, status := range map[string]int{"/": 200, "/api/events": 403} {
		r := httptest.NewRequest("GET", s.origin+path, nil)
		r.Header.Set("Sec-Fetch-Site", "cross-site")
		r.Header.Set("Sec-Fetch-Mode", "navigate")
		w := httptest.NewRecorder()
		s.handler().ServeHTTP(w, r)
		if w.Code != status {
			t.Fatalf("%s: %d", path, w.Code)
		}
	}
}

func TestLANAndEOF(t *testing.T) {
	for _, args := range [][]string{{"serve", "--listen", "0.0.0.0:0"}, {"serve", "--listen", "192.0.2.1:0"}, {"serve", "--listen", "127.0.0.1:0", "--tls-cert", "only"}, {"serve", "--listen", "127.0.0.1:0", "extra"}} {
		if err := run(args, strings.NewReader(""), io.Discard, io.Discard); err == nil {
			t.Fatal(args)
		}
	}
	if err := run([]string{"serve"}, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
}
