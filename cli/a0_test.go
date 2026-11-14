package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func a0Service(t *testing.T) (*service, *client) {
	t.Helper()
	s := newService("http://127.0.0.1:8123", viewerToken)
	actions, err := parseOperatorActions("operator.noop,operator.sleep,operator.exclusiveSleep,monitor.cadence")
	if err != nil {
		t.Fatal(err)
	}
	s.op = newOperator(actions)
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"monitor.cadence", "operator.exclusiveSleep", "operator.noop", "operator.sleep"}}
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	return s, login(t, s)
}

func dispatch(t *testing.T, s *service, c *client, action, args string) string {
	t.Helper()
	id, conf := requestAction(t, c, action, args)
	confirmAction(t, c, conf, action, args)
	drain(s)
	return id
}

func hostIs(host string) func(*http.Request) { return func(r *http.Request) { r.Host = host } }

func loginAt(t *testing.T, s *service, host string) *client {
	t.Helper()
	c := &client{s: s}
	w := c.call("POST", "session", `{"token":"`+s.op.token+`"}`, hostIs(host))
	if w.Code != 204 {
		t.Fatal(w.Code, w.Body)
	}
	c.operator = w.Result().Cookies()[0].Value
	return c
}

func stateFrame(s *service, id, state string, mutate func(*message)) error {
	m := frame("actionState", s.current.Seq+1)
	m.ID, m.State = id, state
	if mutate != nil {
		mutate(&m)
	}
	return s.apply(m)
}

func TestCatalogFileIsValidAndStrict(t *testing.T) {
	if len(catalogEntries) != 7 || entryFor("operator.exclusiveSleep").deadline() != 20*time.Second || !entryFor("operator.exclusiveSleep").Exclusive {
		t.Fatal(catalogIDs())
	}
	base := `{"id":"x.y","tier":"A","scope":"any","deadlineMs":5000,"exclusive":false,"progress":false,"verify":"none","approval":"operator","transport":"any","args":%s}`
	for name, entry := range map[string]string{
		"unanchored pattern":     strings.Replace(base, "%s", `{"a":{"type":"text","pattern":"[a-z]+"}}`, 1),
		"unbounded integer":      strings.Replace(base, "%s", `{"a":{"type":"integer","min":1}}`, 1),
		"unknown type":           strings.Replace(base, "%s", `{"a":{"type":"path"}}`, 1),
		"unknown field":          strings.Replace(base, "%s", `{}`, 1)[:len(base)-4] + `{},"shell":true}`,
		"tier B without host":    strings.Replace(strings.Replace(base, `"tier":"A"`, `"tier":"B"`, 1), "%s", `{}`, 1),
		"deadline too short":     strings.Replace(strings.Replace(base, `5000`, `10`, 1), "%s", `{}`, 1),
		"tier C plain transport": strings.Replace(strings.Replace(strings.Replace(base, `"tier":"A"`, `"tier":"C"`, 1), `"approval":"operator"`, `"approval":"operator+host"`, 1), "%s", `{}`, 1),
	} {
		if _, err := parseCatalog([]byte(`{"version":1,"actions":[` + entry + `]}`)); err == nil {
			t.Fatal(name)
		}
	}
	dup := strings.Replace(base, "%s", `{}`, 1)
	if _, err := parseCatalog([]byte(`{"version":1,"actions":[` + dup + `,` + dup + `]}`)); err == nil {
		t.Fatal("duplicate id")
	}
	sleep := operatorCatalog["operator.sleep"]
	for _, bad := range []string{`{"seconds":0}`, `{"seconds":21}`, `{"seconds":2.0}`, `{"seconds":1e1}`, `{"seconds":"3"}`, `{"seconds":3,"x":1}`} {
		if _, err := sleep(json.RawMessage(bad)); err == nil {
			t.Fatal(bad)
		}
	}
	if got, _ := sleep(json.RawMessage(` {"seconds": 3} `)); string(got) != `{"seconds":3}` {
		t.Fatal(string(got))
	}
}

func TestDeclaredActionStateFields(t *testing.T) {
	s, c := a0Service(t)
	noop := dispatch(t, s, c, "operator.noop", `{"note":"x"}`)
	percent := 50
	for name, mutate := range map[string]func(*message){
		"undeclared progress":   func(m *message) { m.Progress = &progressInfo{Phase: "x", Percent: &percent} },
		"undeclared exclusive":  func(m *message) { m.Exclusive = true },
		"unverified on running": func(m *message) { m.Unverified = true },
	} {
		if stateFrame(s, noop, "running", mutate) == nil {
			t.Fatal(name)
		}
	}
	if stateFrame(s, noop, "completed", nil) == nil {
		t.Fatal("verify:none completion without unverified")
	}
	if err := stateFrame(s, noop, "completed", func(m *message) { m.Unverified = true }); err != nil || !recordOf(s, noop).Unverified {
		t.Fatal(err)
	}
	cadence := dispatch(t, s, c, "monitor.cadence", `{"seconds":5}`)
	if stateFrame(s, cadence, "completed", func(m *message) { m.Unverified = true }) == nil {
		t.Fatal("unverified on a cli-verified action")
	}
	if err := stateFrame(s, cadence, "completed", nil); err != nil {
		t.Fatal(err)
	}
	sleep := dispatch(t, s, c, "operator.sleep", `{"seconds":3}`)
	if err := stateFrame(s, sleep, "running", nil); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []*progressInfo{{Phase: "Sleeping", Percent: &percent}, {Phase: "sleeping"}, {Phase: "sleeping", Percent: new(int)}} {
		if bad.Percent != nil && *bad.Percent == 0 {
			over := 101
			bad.Percent = &over
		}
		if stateFrame(s, sleep, "running", func(m *message) { m.Progress = bad }) == nil {
			t.Fatal("invalid progress", bad)
		}
	}
	if err := stateFrame(s, sleep, "running", func(m *message) { m.Progress = &progressInfo{Phase: "sleeping", Percent: &percent} }); err != nil ||
		recordOf(s, sleep).Progress.Phase != "sleeping" || s.op.late != 0 {
		t.Fatal(err)
	}
	snap := frame("snapshot", s.current.Seq+1)
	snap.Exclusive = true
	if s.apply(snap) == nil {
		t.Fatal("exclusive outside actionState")
	}
}

func TestExclusiveActionPausesSamplingAndRecordsAnonymousBand(t *testing.T) {
	s, c := a0Service(t)
	id := dispatch(t, s, c, "operator.exclusiveSleep", `{"seconds":2}`)
	if stateFrame(s, id, "running", nil) == nil {
		t.Fatal("exclusive action accepted a running frame without exclusive")
	}
	if err := stateFrame(s, id, "running", func(m *message) { m.Exclusive = true }); err != nil {
		t.Fatal(err)
	}
	if !s.mon.paused || s.current.Status != "maintenance" {
		t.Fatal("not paused", s.current.Status)
	}
	if err := s.scheduledRequest(time.Now()); err != nil || len(drain(s)) != 0 || s.mon.pausedSkips != 1 {
		t.Fatal("scheduled sample emitted while paused")
	}
	r := httptest.NewRequest("POST", s.origin+"/api/refresh", nil)
	r.Host, r.Header = "127.0.0.1:8123", http.Header{"Origin": {s.origin}, "X-Dashboard-Action": {"refresh"}}
	r.AddCookie(&http.Cookie{Name: "dashboard", Value: s.cookie})
	w := httptest.NewRecorder()
	s.handler().ServeHTTP(w, r)
	if w.Code != 409 {
		t.Fatal("refresh during maintenance", w.Code)
	}
	s.mu.Lock()
	s.last = time.Now().Add(-20 * time.Second)
	s.mu.Unlock()
	s.expire()
	if s.current.Status != "maintenance" {
		t.Fatal("maintenance shown as stale", s.current.Status)
	}
	viewer, _ := json.Marshal(s.current)
	if strings.Contains(string(viewer), id) || strings.Contains(string(viewer), "exclusiveSleep") {
		t.Fatal("viewer state names the action")
	}
	if err := stateFrame(s, id, "completed", func(m *message) { m.Unverified = true }); err != nil {
		t.Fatal(err)
	}
	if s.mon.paused || s.current.Status != "connected" || len(s.hist.maintenance) != 1 || s.hist.maintenance[0].open {
		t.Fatal("not resumed", s.current.Status, s.hist.maintenance)
	}
	if bands := s.hist.maintenanceIn(time.Now().Add(-time.Minute), time.Now()); len(bands) != 1 || bands[0]["to"] == nil || len(bands[0]) != 2 {
		t.Fatal(bands)
	}
}

func TestExclusiveDeadlineResumesWithUnknownOutcome(t *testing.T) {
	s, c := a0Service(t)
	id := dispatch(t, s, c, "operator.exclusiveSleep", `{"seconds":10}`)
	if err := stateFrame(s, id, "running", func(m *message) { m.Exclusive = true }); err != nil {
		t.Fatal(err)
	}
	s.mu.Lock()
	s.op.dispatchedAt = time.Now().Add(-entryFor("operator.exclusiveSleep").deadline() - time.Second)
	s.mu.Unlock()
	s.expire()
	if r := recordOf(s, id); r.State != "failed" || r.Error != "outcome_unknown" || s.mon.paused {
		t.Fatal("deadline did not resume sampling", r, s.mon.paused)
	}
}

func TestCollectorBusyKeepsTheMonitorUp(t *testing.T) {
	s, _ := a0Service(t)
	id, err := s.request()
	if err != nil {
		t.Fatal(err)
	}
	m := frame("result", s.current.Seq+1)
	ok := false
	m.ID, m.OK, m.Error = id, &ok, "collector_busy"
	if err := s.apply(m); err != nil || s.mon.collectorBusy != 1 || s.current.Status != "connected" {
		t.Fatal(err, s.mon.collectorBusy)
	}
}

func TestTransportRuleForConsequentialTiers(t *testing.T) {
	catalogEntries["test.tierB"] = &catalogEntry{ID: "test.tierB", Tier: "B", Scope: "any", DeadlineMs: 5000, Verify: "native", Approval: "operator+host", Transport: "tls_or_loopback_only"}
	operatorCatalog["test.tierB"] = operatorCatalog["monitor.diagnostics"]
	defer delete(catalogEntries, "test.tierB")
	defer delete(operatorCatalog, "test.tierB")
	for origin, want := range map[string]int{"http://127.0.0.1:8123": 201, "http://[::1]:8123": 201, "https://192.0.2.10:8443": 201, "http://192.0.2.10:8123": 403} {
		s := newService(origin, viewerToken)
		s.op = newOperator(map[string]bool{"test.tierB": true})
		h := frame("hello", 1)
		h.Operator = &operatorCaps{Version: 1, Actions: []string{"test.tierB"}}
		if err := s.apply(h); err != nil {
			t.Fatal(err)
		}
		host := strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
		c := &client{s: s}
		w := c.call("POST", "session", `{"token":"`+s.op.token+`"}`, func(r *http.Request) { r.Host = host })
		c.operator = w.Result().Cookies()[0].Value
		if w := c.call("POST", "request", `{"action":"test.tierB","args":{}}`, func(r *http.Request) { r.Host = host }); w.Code != want {
			t.Fatal(origin, w.Code, w.Body)
		}
	}
}

func TestOperatorStatusPublishesOnlyEnabledCatalog(t *testing.T) {
	_, c := a0Service(t)
	status := decode(t, c.call("GET", "status", ""))
	catalog := status["catalog"].([]any)
	if len(catalog) != 4 {
		t.Fatal(catalog)
	}
	body, _ := json.Marshal(catalog)
	if strings.Contains(string(body), "monitor.diagnostics") || !strings.Contains(string(body), `"max":20`) {
		t.Fatal(string(body))
	}
}
