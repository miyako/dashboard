package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func monitorService(t *testing.T) *service {
	t.Helper()
	s := newService("http://127.0.0.1:8123", viewerToken)
	actions, err := parseOperatorActions("operator.noop,monitor.cadence,monitor.diagnostics")
	if err != nil {
		t.Fatal(err)
	}
	s.op = newOperator(actions)
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"monitor.cadence", "monitor.diagnostics", "operator.noop"}}
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	return s
}

func requestAction(t *testing.T, c *client, action, args string) (id, conf string) {
	t.Helper()
	w := c.call("POST", "request", `{"action":"`+action+`","args":`+args+`}`)
	if w.Code != 201 {
		t.Fatalf("request %d %s", w.Code, w.Body)
	}
	v := decode(t, w)
	return v["id"].(string), v["confirmation"].(string)
}

func confirmAction(t *testing.T, c *client, conf, action, args string) {
	t.Helper()
	if w := c.call("POST", "confirm", `{"confirmation":"`+conf+`","action":"`+action+`","args":`+args+`}`); w.Code != 202 {
		t.Fatalf("confirm %d %s", w.Code, w.Body)
	}
}

func TestMonitorActionArguments(t *testing.T) {
	cadence, diagnostics := operatorCatalog["monitor.cadence"], operatorCatalog["monitor.diagnostics"]
	for _, seconds := range []string{"2", "5", "10"} {
		got, err := cadence(json.RawMessage(`{"seconds":` + seconds + `}`))
		if err != nil || string(got) != `{"seconds":`+seconds+`}` {
			t.Fatal(seconds, err)
		}
	}
	for _, bad := range []string{`{"seconds":1}`, `{"seconds":0}`, `{"seconds":3}`, `{"seconds":60}`, `{"seconds":"5"}`,
		`{"seconds":5.0}`, `{"seconds":5.5}`, `{}`, `{"seconds":5,"force":true}`, `[]`} {
		if _, err := cadence(json.RawMessage(bad)); err == nil {
			t.Fatal(bad)
		}
	}
	if got, err := diagnostics(json.RawMessage(` { } `)); err != nil || string(got) != `{}` {
		t.Fatal(err)
	}
	if _, err := diagnostics(json.RawMessage(`{"verbose":true}`)); err == nil {
		t.Fatal("diagnostics accepted arguments")
	}
	if _, err := parseOperatorActions("monitor.cadence,monitor.restart"); err == nil {
		t.Fatal("accepted a non-catalog monitor action")
	}
}

func TestCadenceIsDefaultDenyAndAppliedOnlyAfterCompletion(t *testing.T) {
	// Enabled for noop only: cadence is a catalog action the host did not list.
	s := operatorService(t)
	c := login(t, s)
	if w := c.call("POST", "request", `{"action":"monitor.cadence","args":{"seconds":5}}`); w.Code != 403 {
		t.Fatal("cadence not default-denied", w.Code)
	}

	s = monitorService(t)
	c = login(t, s)
	id, conf := requestAction(t, c, "monitor.cadence", `{"seconds":5}`)
	confirmAction(t, c, conf, "monitor.cadence", `{"seconds":5}`)
	frames := drain(s)
	if args, _ := json.Marshal(frames[0]["args"]); string(args) != `{"seconds":5}` || frames[0]["action"] != "monitor.cadence" {
		t.Fatal(frames)
	}
	for _, state := range []string{"accepted", "running"} {
		if state == "running" {
			if err := actionState(s, id, "running", ""); err != nil {
				t.Fatal(err)
			}
		}
		if s.mon.cadence != defaultCadence || len(s.mon.cadenceCh) != 0 {
			t.Fatalf("cadence applied while %s", state)
		}
	}
	if err := actionState(s, id, "completed", ""); err != nil {
		t.Fatal(err)
	}
	if s.mon.cadence != 5*time.Second || <-s.mon.cadenceCh != 5*time.Second {
		t.Fatal("completed cadence not handed to the scheduler")
	}
	result, _ := json.Marshal(recordOf(s, id).Result)
	if !strings.Contains(string(result), `"seconds":5`) {
		t.Fatal(string(result))
	}
	status := decode(t, c.call("GET", "status", ""))
	if status["cadence"].(map[string]any)["seconds"] != float64(5) {
		t.Fatal(status["cadence"])
	}
}

func TestCadenceNotAppliedOnFailureOrTimeout(t *testing.T) {
	s := monitorService(t)
	c := login(t, s)
	id, conf := requestAction(t, c, "monitor.cadence", `{"seconds":10}`)
	confirmAction(t, c, conf, "monitor.cadence", `{"seconds":10}`)
	if err := actionState(s, id, "failed", "audit_unavailable"); err != nil {
		t.Fatal(err)
	}
	if s.mon.cadence != defaultCadence || recordOf(s, id).Result != nil {
		t.Fatal("failed cadence applied")
	}
	id, conf = requestAction(t, c, "monitor.cadence", `{"seconds":10}`)
	confirmAction(t, c, conf, "monitor.cadence", `{"seconds":10}`)
	s.mu.Lock()
	s.op.dispatchedAt = time.Now().Add(-actionTimeout - time.Second)
	s.mu.Unlock()
	s.expire()
	if err := actionState(s, id, "completed", ""); err != nil {
		t.Fatal(err)
	}
	r := recordOf(s, id)
	if r.State != "failed" || r.LateState != "completed" || s.mon.cadence != defaultCadence || len(s.mon.cadenceCh) != 0 {
		t.Fatal("late completion applied", r)
	}
}

func TestDiagnosticsAreSanitizedAndOperatorOnly(t *testing.T) {
	s := monitorService(t)
	c := login(t, s)
	id, conf := requestAction(t, c, "monitor.diagnostics", `{}`)
	confirmAction(t, c, conf, "monitor.diagnostics", `{}`)
	if recordOf(s, id).Result != nil {
		t.Fatal("diagnostics before completion")
	}
	if err := actionState(s, id, "completed", ""); err != nil {
		t.Fatal(err)
	}
	result, _ := json.Marshal(recordOf(s, id).Result)
	var d map[string]any
	_ = json.Unmarshal(result, &d)
	for _, key := range []string{"version", "uptimeSeconds", "stream", "cadence", "scheduledRequests", "refreshTimeouts",
		"viewers", "stdoutQueue", "operatorSessions", "actionStates", "lateActionFrames"} {
		if _, ok := d[key]; !ok {
			t.Fatal("missing", key)
		}
	}
	if len(d) != 20 {
		t.Fatal("diagnostics field set changed", len(d))
	}
	for _, secret := range []string{s.token, s.cookie, s.op.token, c.operator, actorOf(c.operator), id, conf, "test-epoch", s.origin, "127.0.0.1"} {
		if strings.Contains(string(result), secret) {
			t.Fatal("diagnostics leaked", secret)
		}
	}
	viewer, _ := json.Marshal(s.current)
	if strings.Contains(string(viewer), "scheduledRequests") || strings.Contains(string(viewer), "cadence") {
		t.Fatal("viewer state gained operator diagnostics")
	}
}

// The real scheduler, with real time: the interval between emitted requests follows the applied cadence.
func TestSchedulerFollowsAppliedCadence(t *testing.T) {
	if testing.Short() {
		t.Skip("real-time scheduler test")
	}
	s := newService("http://127.0.0.1:8123", viewerToken)
	hello(t, s)
	s.mon.cadence = 1100 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	failures := make(chan error, 1)
	done := make(chan error, 1)
	go func() { done <- s.schedule(ctx, failures) }()
	var emitted []time.Time
	answer := func(want int) {
		deadline := time.After(15 * time.Second)
		for len(emitted) < want {
			select {
			case v := <-s.out:
				m := v.(map[string]any)
				if m["kind"] != "request" {
					continue
				}
				emitted = append(emitted, time.Now())
				s.mu.Lock()
				seq := s.current.Seq + 1
				s.mu.Unlock()
				result := frame("result", seq)
				ok := true
				result.ID, result.OK = m["id"].(string), &ok
				if err := s.apply(result); err != nil {
					t.Fatal(err)
				}
			case <-deadline:
				t.Fatal("scheduler stalled")
			}
		}
	}
	answer(3)
	s.mu.Lock()
	s.setCadenceLocked(2200*time.Millisecond, time.Now())
	s.mu.Unlock()
	changed := len(emitted)
	answer(changed + 3)
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	for i := 1; i < changed; i++ {
		if gap := emitted[i].Sub(emitted[i-1]); gap < 900*time.Millisecond || gap > 1600*time.Millisecond {
			t.Fatal("before change", gap)
		}
	}
	for i := changed + 1; i < len(emitted); i++ {
		if gap := emitted[i].Sub(emitted[i-1]); gap < 2000*time.Millisecond || gap > 2700*time.Millisecond {
			t.Fatal("after change", gap)
		}
	}
	s.mu.Lock()
	observed := s.observedIntervalsLocked()
	s.mu.Unlock()
	if len(observed) < 2 || observed[len(observed)-1] < 2000 {
		t.Fatal("observed intervals", observed)
	}
}
