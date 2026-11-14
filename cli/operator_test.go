package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const viewerToken = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func operatorService(t *testing.T) *service {
	t.Helper()
	s := newService("http://127.0.0.1:8123", viewerToken)
	s.op = newOperator(map[string]bool{"operator.noop": true})
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"operator.noop"}}
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	return s
}

type client struct {
	s        *service
	operator string
}

func (c *client) call(method, route, body string, mutate ...func(*http.Request)) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, c.s.origin+"/api/operator/"+route, strings.NewReader(body))
	r.Host = "127.0.0.1:8123"
	if method == "POST" {
		r.Header.Set("Origin", c.s.origin)
		r.Header.Set("X-Dashboard-Action", "operator")
		r.Header.Set("Content-Type", "application/json")
	}
	r.AddCookie(&http.Cookie{Name: "dashboard", Value: c.s.cookie})
	if c.operator != "" {
		r.AddCookie(&http.Cookie{Name: "dashboard_operator", Value: c.operator})
	}
	for _, f := range mutate {
		f(r)
	}
	w := httptest.NewRecorder()
	c.s.handler().ServeHTTP(w, r)
	return w
}

func login(t *testing.T, s *service) *client {
	t.Helper()
	c := &client{s: s}
	w := c.call("POST", "session", `{"token":"`+s.op.token+`"}`)
	if w.Code != 204 {
		t.Fatalf("session %d %s", w.Code, w.Body)
	}
	cookie := w.Result().Cookies()[0]
	if !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/api/operator/" || cookie.Name != "dashboard_operator" {
		t.Fatal(cookie)
	}
	c.operator = cookie.Value
	return c
}

func decode(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var v map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	return v
}

func request(t *testing.T, c *client, note string) (id, conf string) {
	t.Helper()
	w := c.call("POST", "request", `{"action":"operator.noop","args":{"note":"`+note+`"}}`)
	if w.Code != 201 {
		t.Fatalf("request %d %s", w.Code, w.Body)
	}
	v := decode(t, w)
	return v["id"].(string), v["confirmation"].(string)
}

func confirm(c *client, conf, note string) *httptest.ResponseRecorder {
	return c.call("POST", "confirm", `{"confirmation":"`+conf+`","action":"operator.noop","args":{"note":"`+note+`"}}`)
}

func drain(s *service) []map[string]any {
	var frames []map[string]any
	for {
		select {
		case v := <-s.out:
			body, _ := json.Marshal(v)
			var m map[string]any
			_ = json.Unmarshal(body, &m)
			frames = append(frames, m)
		default:
			return frames
		}
	}
}

func actionState(s *service, id, state, code string) error {
	m := frame("actionState", s.current.Seq+1)
	m.ID, m.State, m.Error = id, state, code
	return s.apply(m)
}

func recordOf(s *service, id string) *actionRecord { return s.op.record(id) }

func TestOperatorDisabledByDefault(t *testing.T) {
	s := newService("http://127.0.0.1:8123", viewerToken)
	hello(t, s)
	c := &client{s: s}
	for _, route := range []string{"status", "session", "request"} {
		method := "POST"
		if route == "status" {
			method = "GET"
		}
		if w := c.call(method, route, `{}`); w.Code != 404 {
			t.Fatalf("%s %d", route, w.Code)
		}
	}
	// A hello declaring operator mode the CLI did not enable is a protocol error.
	s2 := newService("http://127.0.0.1:8123", viewerToken)
	h := frame("hello", 1)
	h.Operator = &operatorCaps{Version: 1, Actions: []string{"operator.noop"}}
	if s2.apply(h) == nil {
		t.Fatal("accepted undeclared operator capability")
	}
}

func TestOperatorNegotiationAndFrameScoping(t *testing.T) {
	for name, caps := range map[string]*operatorCaps{
		"missing":   nil,
		"version":   {Version: 2, Actions: []string{"operator.noop"}},
		"extra":     {Version: 1, Actions: []string{"operator.noop", "operator.other"}},
		"duplicate": {Version: 1, Actions: []string{"operator.noop", "operator.noop"}},
		"empty":     {Version: 1},
	} {
		s := newService("http://127.0.0.1:8123", viewerToken)
		s.op = newOperator(map[string]bool{"operator.noop": true})
		h := frame("hello", 1)
		h.Operator = caps
		if s.apply(h) == nil {
			t.Fatal(name)
		}
	}
	s := operatorService(t)
	m := frame("snapshot", 2)
	m.Operator = &operatorCaps{Version: 1}
	if s.apply(m) == nil {
		t.Fatal("operator declaration outside hello")
	}
	m = frame("snapshot", 2)
	m.State = "completed"
	if s.apply(m) == nil {
		t.Fatal("state outside actionState")
	}
	for _, list := range []string{"", "operator.noop,operator.noop", "operator.shell", "operator.noop,"} {
		if _, err := parseOperatorActions(list); err == nil {
			t.Fatal(list)
		}
	}
}

func TestOperatorAuthenticationBoundaries(t *testing.T) {
	s := operatorService(t)
	c := &client{s: s}
	good := `{"token":"` + s.op.token + `"}`
	for name, test := range map[string]struct {
		body   string
		mutate func(*http.Request)
		status int
	}{
		"wrong token":    {`{"token":"` + strings.Repeat("b", 64) + `"}`, nil, 401},
		"viewer token":   {`{"token":"` + viewerToken + `"}`, nil, 401},
		"unknown field":  {`{"token":"x","role":"admin"}`, nil, 400},
		"two objects":    {good + good, nil, 400},
		"oversized":      {`{"token":"` + strings.Repeat("a", 2000) + `"}`, nil, 413},
		"cross origin":   {good, func(r *http.Request) { r.Header.Set("Origin", "http://evil.example") }, 403},
		"no header":      {good, func(r *http.Request) { r.Header.Del("X-Dashboard-Action") }, 403},
		"refresh header": {good, func(r *http.Request) { r.Header.Set("X-Dashboard-Action", "refresh") }, 403},
		"form encoded":   {good, func(r *http.Request) { r.Header.Set("Content-Type", "text/plain") }, 403},
		"wrong host":     {good, func(r *http.Request) { r.Host = "evil.example" }, 403},
		"no viewer":      {good, func(r *http.Request) { r.Header.Del("Cookie") }, 401},
		"cross-site":     {good, func(r *http.Request) { r.Header.Set("Sec-Fetch-Site", "cross-site") }, 403},
	} {
		if w := c.call("POST", "session", test.body, func(r *http.Request) {
			if test.mutate != nil {
				test.mutate(r)
			}
		}); w.Code != test.status {
			t.Fatalf("%s: %d %s", name, w.Code, w.Body)
		}
	}
	// The viewer cookie alone confers no operator authority.
	if w := c.call("GET", "status", ""); w.Code != 401 {
		t.Fatal(w.Code)
	}
	if w := c.call("POST", "request", `{"action":"operator.noop","args":{"note":"x"}}`); w.Code != 401 {
		t.Fatal(w.Code)
	}
	forged := &client{s: s, operator: strings.Repeat("c", 64)}
	if w := forged.call("GET", "status", ""); w.Code != 401 {
		t.Fatal(w.Code)
	}
	for i := 0; i < maxOperatorSessions; i++ {
		login(t, s)
	}
	if w := c.call("POST", "session", good); w.Code != 429 {
		t.Fatal("session limit", w.Code)
	}
}

func TestOperatorSessionExpiry(t *testing.T) {
	s := operatorService(t)
	idle, absolute := login(t, s), login(t, s)
	_, conf := request(t, idle, "idle")
	s.mu.Lock()
	for _, session := range s.op.sessions {
		if session.actor == actorOf(idle.operator) {
			session.seen = time.Now().Add(-operatorIdle - time.Second)
		} else {
			session.created = time.Now().Add(-operatorAbsolute - time.Second)
		}
	}
	s.mu.Unlock()
	for _, c := range []*client{idle, absolute} {
		if w := c.call("GET", "status", ""); w.Code != 401 {
			t.Fatal("expired session accepted", w.Code)
		}
	}
	if _, ok := s.op.confirmations[conf]; ok {
		t.Fatal("expired session kept its confirmation")
	}
}

func TestOperatorRequestValidation(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	operatorCatalog["test.disabled"] = operatorCatalog["operator.noop"]
	defer delete(operatorCatalog, "test.disabled")
	for name, test := range map[string]struct {
		body   string
		status int
	}{
		"unknown action": {`{"action":"operator.shell","args":{"note":"x"}}`, 400},
		"default deny":   {`{"action":"test.disabled","args":{"note":"x"}}`, 403},
		"missing note":   {`{"action":"operator.noop","args":{}}`, 400},
		"extra arg":      {`{"action":"operator.noop","args":{"note":"x","path":"/etc"}}`, 400},
		"long note":      {`{"action":"operator.noop","args":{"note":"` + strings.Repeat("x", 33) + `"}}`, 400},
		"unsafe note":    {`{"action":"operator.noop","args":{"note":"a;rm"}}`, 400},
		"non-text note":  {`{"action":"operator.noop","args":{"note":1}}`, 400},
		"unknown field":  {`{"action":"operator.noop","args":{"note":"x"},"force":true}`, 400},
		"missing args":   {`{"action":"operator.noop"}`, 400},
	} {
		s.op.requests = nil
		if w := c.call("POST", "request", test.body); w.Code != test.status {
			t.Fatalf("%s: %d %s", name, w.Code, w.Body)
		}
	}
	// Rejected attempts count against the six-per-minute budget too.
	s.op.requests = nil
	for i := 0; i < actionRequestRate; i++ {
		c.call("POST", "request", `{"action":"operator.shell","args":{}}`)
	}
	if w := c.call("POST", "request", `{"action":"operator.noop","args":{"note":"x"}}`); w.Code != 429 {
		t.Fatal("rate limit", w.Code)
	}
	s.op.requests = nil
	for i := 0; i < maxConfirmations; i++ {
		request(t, c, "ok")
	}
	if w := c.call("POST", "request", `{"action":"operator.noop","args":{"note":"x"}}`); w.Code != 429 || decode(t, w)["error"] != "confirmation_limit" {
		t.Fatal("confirmation limit", w.Code)
	}
}

func TestOperatorConfirmationLifecycle(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	id, conf := request(t, c, "first note")
	if recordOf(s, id).State != "requested" || len(drain(s)) != 0 {
		t.Fatal("request dispatched before confirmation")
	}
	w := confirm(c, conf, "first note")
	if w.Code != 202 || recordOf(s, id).State != "accepted" {
		t.Fatal(w.Code, w.Body)
	}
	frames := drain(s)
	if len(frames) != 1 {
		t.Fatal(frames)
	}
	f := frames[0]
	args, _ := json.Marshal(f["args"])
	if f["kind"] != "action" || f["epoch"] != "test-epoch" || f["id"] != id || f["action"] != "operator.noop" ||
		string(args) != `{"note":"first note"}` || f["actor"] != actorOf(c.operator) || len(f) != 7 {
		t.Fatal(f)
	}
	// Replay of a consumed confirmation.
	if w := confirm(c, conf, "first note"); w.Code != 409 || decode(t, w)["error"] != "unknown_confirmation" {
		t.Fatal("replay", w.Code)
	}
	if err := actionState(s, id, "running", ""); err != nil || recordOf(s, id).State != "running" {
		t.Fatal(err)
	}
	if err := actionState(s, id, "completed", ""); err != nil || recordOf(s, id).State != "completed" || s.op.inflight != nil {
		t.Fatal(err)
	}
	if s.op.generation != 2 {
		t.Fatal("generation did not advance", s.op.generation)
	}
	// Duplicate and late frames for a finished ID are ignored without changing the outcome.
	if err := actionState(s, id, "failed", "late_failure"); err != nil || recordOf(s, id).State != "completed" || s.op.late != 1 {
		t.Fatal(err, recordOf(s, id))
	}
	if actionState(s, strings.Repeat("d", 64), "completed", "") == nil {
		t.Fatal("accepted uncorrelated actionState")
	}
}

func TestOperatorConfirmationRejections(t *testing.T) {
	s := operatorService(t)
	owner, other := login(t, s), login(t, s)

	id, conf := request(t, owner, "abc")
	if w := confirm(other, conf, "abc"); w.Code != 403 || recordOf(s, id).State != "cancelled" || recordOf(s, id).Error != "wrong_actor" {
		t.Fatal("wrong actor", w.Code)
	}
	if w := confirm(owner, conf, "abc"); w.Code != 409 {
		t.Fatal("confirmation survived a failed attempt")
	}

	id, conf = request(t, owner, "abc")
	if w := confirm(owner, conf, "abd"); w.Code != 409 || recordOf(s, id).Error != "argument_mismatch" {
		t.Fatal("argument mismatch", w.Code)
	}
	id, conf = request(t, owner, "abc")
	if w := owner.call("POST", "confirm", `{"confirmation":"`+conf+`","action":"test.other","args":{"note":"abc"}}`); w.Code != 409 || recordOf(s, id).Error != "argument_mismatch" {
		t.Fatal("action mismatch", w.Code)
	}

	id, conf = request(t, owner, "abc")
	s.op.confirmations[conf].expires = time.Now().Add(-time.Millisecond)
	if w := confirm(owner, conf, "abc"); w.Code != 409 || recordOf(s, id).Error != "expired" {
		t.Fatal("expired", w.Code, w.Body)
	}

	id, conf = request(t, owner, "abc")
	s.op.confirmations[conf].epoch = "other-epoch"
	if w := confirm(owner, conf, "abc"); w.Code != 409 || recordOf(s, id).Error != "stale_target" {
		t.Fatal("epoch", w.Code)
	}

	// Generation: a confirmation issued before another action finished is stale.
	s.op.requests = nil
	first, firstConf := request(t, owner, "one")
	second, secondConf := request(t, owner, "two")
	if w := confirm(owner, firstConf, "one"); w.Code != 202 {
		t.Fatal(w.Code)
	}
	if w := confirm(owner, secondConf, "two"); w.Code != 409 || recordOf(s, second).Error != "busy" {
		t.Fatal("busy", w.Code, w.Body)
	}
	third, thirdConf := request(t, owner, "three")
	if err := actionState(s, first, "completed", ""); err != nil {
		t.Fatal(err)
	}
	if w := confirm(owner, thirdConf, "three"); w.Code != 409 || recordOf(s, third).Error != "stale_target" {
		t.Fatal("generation", w.Code)
	}
	drain(s)
}

func TestOperatorStaleTargetAndTimeout(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	id, conf := request(t, c, "x")
	if w := confirm(c, conf, "x"); w.Code != 202 {
		t.Fatal(w.Code)
	}
	_, pending := request(t, c, "y")
	generation := s.op.generation
	s.mu.Lock()
	s.last = time.Now().Add(-16 * time.Second)
	s.mu.Unlock()
	s.expire()
	if s.current.Status != "stale" || s.op.generation != generation+1 {
		t.Fatal("stale did not advance generation")
	}
	if _, ok := s.op.confirmations[pending]; ok {
		t.Fatal("stale target kept a confirmation")
	}
	if w := c.call("POST", "request", `{"action":"operator.noop","args":{"note":"z"}}`); w.Code != 409 || decode(t, w)["error"] != "target_unavailable" {
		t.Fatal("request on stale target", w.Code)
	}
	// The in-flight action times out with an unknown outcome; a late result is recorded, never applied.
	s.mu.Lock()
	s.op.dispatchedAt = time.Now().Add(-actionTimeout - time.Second)
	s.mu.Unlock()
	s.expire()
	r := recordOf(s, id)
	if r.State != "failed" || r.Error != "outcome_unknown" || s.op.inflight != nil {
		t.Fatal(r)
	}
	if err := actionState(s, id, "completed", ""); err != nil || r.State != "failed" || r.LateState != "completed" {
		t.Fatal(err, r)
	}
	if len(drain(s)) != 1 {
		t.Fatal("automatic retry or extra dispatch")
	}
}

func TestOperatorActionStateValidation(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	id, conf := request(t, c, "x")
	confirm(c, conf, "x")
	for name, m := range map[string][2]string{
		"bad state":       {"cancelled", ""},
		"failed no code":  {"failed", ""},
		"code on success": {"completed", "oops"},
		"code on running": {"running", "audit_incomplete"},
		"bad code":        {"failed", "Not-A-Code"},
	} {
		if actionState(s, id, m[0], m[1]) == nil {
			t.Fatal(name)
		}
	}
	if actionState(s, "short", "running", "") == nil {
		t.Fatal("bad id")
	}
	// Out of order: completion straight from accepted is final, and may flag an incomplete audit.
	if err := actionState(s, id, "completed", "audit_incomplete"); err != nil || recordOf(s, id).State != "completed" || recordOf(s, id).Error != "audit_incomplete" {
		t.Fatal(err)
	}
	if err := actionState(s, id, "running", ""); err != nil || recordOf(s, id).State != "completed" {
		t.Fatal("late running changed the state")
	}
	plain := newService("http://127.0.0.1:8123", viewerToken)
	hello(t, plain)
	if actionState(plain, id, "running", "") == nil {
		t.Fatal("actionState without operator mode")
	}
}

func TestOperatorInterleavesWithRefresh(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	id, conf := request(t, c, "x")
	confirm(c, conf, "x")
	refresh, err := s.request()
	if err != nil {
		t.Fatal(err)
	}
	if err := actionState(s, id, "running", ""); err != nil {
		t.Fatal(err)
	}
	result := frame("result", s.current.Seq+1)
	ok := true
	result.ID, result.OK = refresh, &ok
	if err := s.apply(result); err != nil || s.pending != "" {
		t.Fatal(err)
	}
	if err := actionState(s, id, "completed", ""); err != nil {
		t.Fatal(err)
	}
	// A refresh result never resolves an action, nor an actionState a refresh.
	result = frame("result", s.current.Seq+1)
	result.ID, result.OK = id, &ok
	if s.apply(result) == nil {
		t.Fatal("refresh result correlated to an action")
	}
}

func TestOperatorCancelLogoutAndPrivacy(t *testing.T) {
	s := operatorService(t)
	owner, other := login(t, s), login(t, s)
	id, conf := request(t, owner, "sentinelnote")
	if w := other.call("POST", "cancel", `{"id":"`+id+`"}`); w.Code != 404 {
		t.Fatal("cancelled another actor's action", w.Code)
	}
	if w := owner.call("POST", "cancel", `{"id":"`+id+`"}`); w.Code != 200 || recordOf(s, id).State != "cancelled" {
		t.Fatal(w.Code)
	}
	if w := confirm(owner, conf, "sentinelnote"); w.Code != 409 {
		t.Fatal("confirmed a withdrawn action")
	}
	id, conf = request(t, owner, "sentinelnote")
	confirm(owner, conf, "sentinelnote")
	if w := owner.call("POST", "cancel", `{"id":"`+id+`"}`); w.Code != 409 {
		t.Fatal("cancelled a dispatched action", w.Code)
	}
	// Status is per actor and never echoes secrets.
	status := owner.call("GET", "status", "")
	if status.Code != 200 || strings.Count(status.Body.String(), `"id":"`) != 2 {
		t.Fatal(status.Body)
	}
	if body := other.call("GET", "status", "").Body.String(); strings.Contains(body, id) {
		t.Fatal("status leaked another actor's actions")
	}
	viewer, _ := json.Marshal(s.current)
	for _, secret := range []string{s.op.token, owner.operator, id, conf, "sentinelnote", actorOf(owner.operator)} {
		if strings.Contains(status.Body.String(), secret) && secret != id {
			t.Fatal("status leaked a secret")
		}
		if strings.Contains(string(viewer), secret) {
			t.Fatal("viewer state leaked operator data")
		}
	}
	_, pending := request(t, owner, "later")
	if w := owner.call("POST", "logout", `{}`); w.Code != 204 {
		t.Fatal(w.Code)
	}
	if _, ok := s.op.confirmations[pending]; ok {
		t.Fatal("logout kept a confirmation")
	}
	if w := owner.call("GET", "status", ""); w.Code != 401 {
		t.Fatal("session survived logout")
	}
}

func TestOperatorStdoutBackpressureRejectsDispatch(t *testing.T) {
	s := operatorService(t)
	c := login(t, s)
	for len(s.out) < cap(s.out) {
		s.out <- map[string]any{}
	}
	id, conf := request(t, c, "x")
	if w := confirm(c, conf, "x"); w.Code != 503 || recordOf(s, id).State != "cancelled" || s.op.inflight != nil {
		t.Fatal(w.Code, errors.New(w.Body.String()))
	}
}

func TestOperatorHistoryIsBoundedAndKeepsLiveRecords(t *testing.T) {
	o := newOperator(map[string]bool{"operator.noop": true})
	pending := &actionRecord{ID: "pending", State: "requested"}
	o.addRecord(pending)
	for i := 0; i < maxActionRecords*2; i++ {
		o.addRecord(&actionRecord{ID: fmt.Sprint(i), State: "completed"})
	}
	if len(o.records) != maxActionRecords || o.record("pending") == nil || o.record("0") != nil {
		t.Fatal(len(o.records))
	}
}
