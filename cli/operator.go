package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Operator limits; see docs/operator-actions.md.
const (
	operatorIdle        = 15 * time.Minute
	operatorAbsolute    = 60 * time.Minute
	confirmationTTL     = 60 * time.Second
	actionTimeout       = 30 * time.Second
	maxOperatorSessions = 4
	maxConfirmations    = 4
	actionRequestRate   = 6
	maxOperatorBody     = 1024
	maxActionRecords    = 16
	maxFinishedIDs      = 32
	operatorProtocol    = 1
)

var noopNote = regexp.MustCompile(`^[A-Za-z0-9 _.-]{1,32}$`)
var errorCode = regexp.MustCompile(`^[a-z_]{1,64}$`)
var hex64 = regexp.MustCompile(`^[a-f0-9]{64}$`)

// operatorCatalog is the closed action list. Each entry returns canonical JSON arguments.
var operatorCatalog = map[string]func(json.RawMessage) (json.RawMessage, error){
	"operator.noop": func(raw json.RawMessage) (json.RawMessage, error) {
		var args struct {
			Note *string `json:"note"`
		}
		if err := strictDecode(raw, &args); err != nil || args.Note == nil || !noopNote.MatchString(*args.Note) {
			return nil, errors.New("operator.noop requires note: 1..32 of A-Z a-z 0-9 space _ . -")
		}
		return json.Marshal(map[string]string{"note": *args.Note})
	},
}

type operatorCaps struct {
	Version int      `json:"version"`
	Actions []string `json:"actions"`
}

type operatorSession struct {
	actor         string
	created, seen time.Time
}

type confirmation struct {
	id, record, actor, action, epoch string
	args                             json.RawMessage
	generation                       uint64
	expires                          time.Time
}

type actionRecord struct {
	ID        string `json:"id"`
	Action    string `json:"action"`
	State     string `json:"state"`
	Error     string `json:"error,omitempty"`
	LateState string `json:"lateState,omitempty"`
	Requested string `json:"requestedAt"`
	Updated   string `json:"updatedAt"`
	actor     string
	args      json.RawMessage
}

type operator struct {
	token         string
	actions       map[string]bool
	negotiated    bool
	sessions      map[string]*operatorSession
	confirmations map[string]*confirmation
	records       []*actionRecord
	inflight      *actionRecord
	dispatchedAt  time.Time
	requests      []time.Time
	generation    uint64
	finished      []string
	late          int
}

func parseOperatorActions(list string) (map[string]bool, error) {
	actions := map[string]bool{}
	for _, id := range strings.Split(list, ",") {
		if _, ok := operatorCatalog[id]; !ok || actions[id] {
			return nil, errors.New("operator actions must be unique catalog IDs")
		}
		actions[id] = true
	}
	if len(actions) == 0 || len(actions) > 8 {
		return nil, errors.New("operator actions must list 1..8 catalog IDs")
	}
	return actions, nil
}

func newOperator(actions map[string]bool) *operator {
	return &operator{token: nonce(), actions: actions, generation: 1,
		sessions: map[string]*operatorSession{}, confirmations: map[string]*confirmation{}}
}

func (o *operator) caps() operatorCaps {
	caps := operatorCaps{Version: operatorProtocol}
	for id := range o.actions {
		caps.Actions = append(caps.Actions, id)
	}
	sort.Strings(caps.Actions)
	return caps
}

func strictDecode(raw []byte, v any) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(v); err != nil {
		return err
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("exactly one JSON object required")
	}
	return nil
}

func actorOf(session string) string {
	sum := sha256.Sum256([]byte(session))
	return hex.EncodeToString(sum[:8])
}

func stamp(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

// negotiateLocked validates the hello's operator declaration against the CLI's own opt-in.
func (s *service) negotiateLocked(caps *operatorCaps) error {
	if s.op == nil {
		if caps != nil {
			return errors.New("hello declares operator actions the CLI did not enable")
		}
		return nil
	}
	if caps == nil || caps.Version != operatorProtocol || len(caps.Actions) != len(s.op.actions) {
		return errors.New("hello operator declaration does not match the CLI")
	}
	seen := map[string]bool{}
	for _, id := range caps.Actions {
		if !s.op.actions[id] || seen[id] {
			return errors.New("hello operator declaration does not match the CLI")
		}
		seen[id] = true
	}
	s.op.negotiated = true
	return nil
}

func (o *operator) record(id string) *actionRecord {
	for _, r := range o.records {
		if r.ID == id {
			return r
		}
	}
	return nil
}

func (o *operator) transition(r *actionRecord, state, reason string, now time.Time) {
	r.State, r.Error, r.Updated = state, reason, stamp(now)
}

// finishLocked ends the in-flight action and advances the generation.
func (o *operator) finish(r *actionRecord, state, reason string, now time.Time) {
	o.transition(r, state, reason, now)
	o.inflight = nil
	o.generation++
	o.finished = append(o.finished, r.ID)
	if len(o.finished) > maxFinishedIDs {
		o.finished = o.finished[len(o.finished)-maxFinishedIDs:]
	}
}

func (o *operator) addRecord(r *actionRecord) {
	o.records = append(o.records, r)
	if len(o.records) <= maxActionRecords {
		return
	}
	// Drop the oldest record that is not pending or in flight.
	for i, old := range o.records {
		if old.State == "completed" || old.State == "failed" || old.State == "cancelled" {
			o.records = append(o.records[:i], o.records[i+1:]...)
			return
		}
	}
}

func (o *operator) withdraw(c *confirmation, reason string, now time.Time) {
	delete(o.confirmations, c.id)
	if r := o.record(c.record); r != nil && r.State == "requested" {
		o.transition(r, "cancelled", reason, now)
	}
}

// expire applies session, confirmation and in-flight deadlines; stale invalidates pending confirmations.
func (o *operator) expire(now time.Time, stale bool) {
	for id, session := range o.sessions {
		if now.Sub(session.seen) > operatorIdle || now.Sub(session.created) > operatorAbsolute {
			delete(o.sessions, id)
			for _, c := range o.confirmations {
				if c.actor == session.actor {
					o.withdraw(c, "session_expired", now)
				}
			}
		}
	}
	for _, c := range o.confirmations {
		if now.After(c.expires) {
			o.withdraw(c, "expired", now)
		} else if stale {
			o.withdraw(c, "stale_target", now)
		}
	}
	if o.inflight != nil && now.Sub(o.dispatchedAt) > actionTimeout {
		// It may still have run: the outcome is unknown, never assumed failed or retried.
		o.finish(o.inflight, "failed", "outcome_unknown", now)
	}
}

// applyActionStateLocked handles a 4D actionState frame.
func (s *service) applyActionStateLocked(m message) error {
	if s.op == nil || !s.op.negotiated {
		return errors.New("actionState without negotiated operator mode")
	}
	// failed needs a code; completed may carry only audit_incomplete; running carries none.
	validError := (m.State == "failed" && errorCode.MatchString(m.Error)) ||
		(m.State == "completed" && (m.Error == "" || m.Error == "audit_incomplete")) ||
		(m.State == "running" && m.Error == "")
	if !hex64.MatchString(m.ID) || !validError {
		return errors.New("invalid actionState frame")
	}
	now := time.Now()
	o := s.op
	if o.inflight != nil && o.inflight.ID == m.ID {
		r := o.inflight
		switch {
		case m.State == "running" && r.State == "accepted":
			o.transition(r, "running", "", now)
		case m.State == "running":
			o.late++ // duplicate running frame; no state change
		default:
			o.finish(r, m.State, m.Error, now)
		}
		return nil
	}
	for _, id := range o.finished {
		if id == m.ID {
			// Late or duplicate: consumes its sequence, never changes the recorded outcome.
			o.late++
			if r := o.record(id); r != nil && r.Error == "outcome_unknown" && m.State != "running" {
				r.LateState = m.State
			}
			return nil
		}
	}
	return errors.New("uncorrelated actionState")
}

func operatorError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": code})
}

func operatorJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// operatorRoute serves /api/operator/*; the viewer cookie was already verified.
func (s *service) operatorRoute(w http.ResponseWriter, r *http.Request) {
	if s.op == nil {
		http.NotFound(w, r)
		return
	}
	route := strings.TrimPrefix(r.URL.Path, "/api/operator/")
	if route == "status" {
		if r.Method != "GET" {
			operatorError(w, 405, "get_required")
			return
		}
	} else if r.Method != "POST" || r.Header.Get("Origin") != s.origin || r.Header.Get("X-Dashboard-Action") != "operator" ||
		!strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		operatorError(w, 403, "same_origin_operator_post_required")
		return
	}
	var body []byte
	if r.Method == "POST" {
		var err error
		body, err = io.ReadAll(http.MaxBytesReader(w, r.Body, maxOperatorBody))
		if err != nil {
			operatorError(w, 413, "body_too_large")
			return
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.op.expire(now, s.current.Status == "stale")
	if route == "session" {
		s.operatorSessionLocked(w, body, now)
		return
	}
	cookie, err := r.Cookie("dashboard_operator")
	if err != nil {
		operatorError(w, 401, "operator_authentication_required")
		return
	}
	var session *operatorSession
	for id, candidate := range s.op.sessions {
		if sameSecret(id, cookie.Value) {
			session = candidate
		}
	}
	if session == nil {
		operatorError(w, 401, "operator_authentication_required")
		return
	}
	session.seen = now
	switch route {
	case "status":
		s.operatorStatusLocked(w, session, now)
	case "request":
		s.operatorRequestLocked(w, body, session, now)
	case "confirm":
		s.operatorConfirmLocked(w, body, session, now)
	case "cancel":
		s.operatorCancelLocked(w, body, session, now)
	case "logout":
		if strictDecode(body, &struct{}{}) != nil {
			operatorError(w, 400, "invalid_body")
			return
		}
		for id, candidate := range s.op.sessions {
			if candidate == session {
				delete(s.op.sessions, id)
			}
		}
		for _, c := range s.op.confirmations {
			if c.actor == session.actor {
				s.op.withdraw(c, "logged_out", now)
			}
		}
		http.SetCookie(w, &http.Cookie{Name: "dashboard_operator", Value: "", Path: "/api/operator/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode, Secure: strings.HasPrefix(s.origin, "https:")})
		w.WriteHeader(204)
	default:
		operatorError(w, 404, "unknown_route")
	}
}

func (s *service) operatorSessionLocked(w http.ResponseWriter, body []byte, now time.Time) {
	var req struct {
		Token *string `json:"token"`
	}
	if strictDecode(body, &req) != nil || req.Token == nil {
		operatorError(w, 400, "invalid_body")
		return
	}
	if !sameSecret(*req.Token, s.op.token) {
		operatorError(w, 401, "invalid_operator_token")
		return
	}
	if len(s.op.sessions) >= maxOperatorSessions {
		operatorError(w, 429, "operator_session_limit")
		return
	}
	id := nonce()
	s.op.sessions[id] = &operatorSession{actor: actorOf(id), created: now, seen: now}
	http.SetCookie(w, &http.Cookie{Name: "dashboard_operator", Value: id, Path: "/api/operator/", HttpOnly: true, SameSite: http.SameSiteStrictMode, Secure: strings.HasPrefix(s.origin, "https:")})
	w.WriteHeader(204)
}

func (s *service) operatorStatusLocked(w http.ResponseWriter, session *operatorSession, now time.Time) {
	type pending struct {
		Confirmation string          `json:"confirmation"`
		ID           string          `json:"id"`
		Action       string          `json:"action"`
		Args         json.RawMessage `json:"args"`
		ExpiresAt    string          `json:"expiresAt"`
	}
	records, confirmations := []*actionRecord{}, []pending{}
	for _, r := range s.op.records {
		if r.actor == session.actor {
			records = append(records, r)
		}
	}
	for _, c := range s.op.confirmations {
		if c.actor == session.actor {
			confirmations = append(confirmations, pending{c.id, c.record, c.action, c.args, stamp(c.expires)})
		}
	}
	sort.Slice(confirmations, func(i, j int) bool { return confirmations[i].ExpiresAt < confirmations[j].ExpiresAt })
	expires := session.seen.Add(operatorIdle)
	if absolute := session.created.Add(operatorAbsolute); absolute.Before(expires) {
		expires = absolute
	}
	operatorJSON(w, 200, map[string]any{"actions": s.op.caps().Actions, "generation": s.op.generation,
		"busy": s.op.inflight != nil, "target": s.current.Status, "sessionExpiresAt": stamp(expires),
		"confirmations": confirmations, "records": records})
}

func (s *service) targetReadyLocked() bool {
	return s.op.negotiated && s.current.Epoch != "" && s.current.Status == "connected"
}

func (s *service) operatorRequestLocked(w http.ResponseWriter, body []byte, session *operatorSession, now time.Time) {
	var req struct {
		Action *string          `json:"action"`
		Args   *json.RawMessage `json:"args"`
	}
	if strictDecode(body, &req) != nil || req.Action == nil || req.Args == nil {
		operatorError(w, 400, "invalid_body")
		return
	}
	window := s.op.requests[:0]
	for _, at := range s.op.requests {
		if now.Sub(at) < time.Minute {
			window = append(window, at)
		}
	}
	s.op.requests = window
	if len(s.op.requests) >= actionRequestRate {
		operatorError(w, 429, "rate_limited")
		return
	}
	s.op.requests = append(s.op.requests, now)
	canonical, known := operatorCatalog[*req.Action]
	if !known {
		operatorError(w, 400, "unknown_action")
		return
	}
	if !s.op.actions[*req.Action] {
		operatorError(w, 403, "action_not_enabled")
		return
	}
	args, err := canonical(*req.Args)
	if err != nil {
		operatorError(w, 400, "invalid_arguments")
		return
	}
	if !s.targetReadyLocked() {
		operatorError(w, 409, "target_unavailable")
		return
	}
	if len(s.op.confirmations) >= maxConfirmations {
		operatorError(w, 429, "confirmation_limit")
		return
	}
	r := &actionRecord{ID: nonce(), Action: *req.Action, State: "requested", Requested: stamp(now), Updated: stamp(now), actor: session.actor, args: args}
	c := &confirmation{id: nonce(), record: r.ID, actor: session.actor, action: r.Action, epoch: s.current.Epoch,
		args: args, generation: s.op.generation, expires: now.Add(confirmationTTL)}
	s.op.addRecord(r)
	s.op.confirmations[c.id] = c
	operatorJSON(w, 201, map[string]any{"id": r.ID, "confirmation": c.id, "action": c.action, "args": c.args, "expiresAt": stamp(c.expires)})
}

func (s *service) operatorConfirmLocked(w http.ResponseWriter, body []byte, session *operatorSession, now time.Time) {
	var req struct {
		Confirmation *string          `json:"confirmation"`
		Action       *string          `json:"action"`
		Args         *json.RawMessage `json:"args"`
	}
	if strictDecode(body, &req) != nil || req.Confirmation == nil || req.Action == nil || req.Args == nil {
		operatorError(w, 400, "invalid_body")
		return
	}
	var c *confirmation
	for id, candidate := range s.op.confirmations {
		if sameSecret(id, *req.Confirmation) {
			c = candidate
		}
	}
	if c == nil {
		operatorError(w, 409, "unknown_confirmation")
		return
	}
	// Single use: consumed by this attempt whatever its outcome.
	delete(s.op.confirmations, c.id)
	r := s.op.record(c.record)
	reject := func(status int, reason string) {
		if r != nil && r.State == "requested" {
			s.op.transition(r, "cancelled", reason, now)
		}
		operatorError(w, status, reason)
	}
	if c.actor != session.actor {
		reject(403, "wrong_actor")
		return
	}
	if now.After(c.expires) {
		reject(409, "expired")
		return
	}
	var args json.RawMessage
	if canonical, ok := operatorCatalog[*req.Action]; ok {
		args, _ = canonical(*req.Args)
	}
	if *req.Action != c.action || args == nil || !bytes.Equal(args, c.args) {
		reject(409, "argument_mismatch")
		return
	}
	if c.epoch != s.current.Epoch || c.generation != s.op.generation || !s.targetReadyLocked() {
		reject(409, "stale_target")
		return
	}
	if s.op.inflight != nil {
		reject(409, "busy")
		return
	}
	if r == nil || r.State != "requested" {
		reject(409, "unknown_confirmation")
		return
	}
	if err := s.emit(map[string]any{"protocol": 1, "kind": "action", "epoch": s.current.Epoch, "id": r.ID,
		"action": r.Action, "args": r.args, "actor": r.actor}); err != nil {
		reject(503, "dispatch_failed")
		return
	}
	s.op.transition(r, "accepted", "", now)
	s.op.inflight, s.op.dispatchedAt = r, now
	operatorJSON(w, 202, map[string]string{"id": r.ID, "state": r.State})
}

func (s *service) operatorCancelLocked(w http.ResponseWriter, body []byte, session *operatorSession, now time.Time) {
	var req struct {
		ID *string `json:"id"`
	}
	if strictDecode(body, &req) != nil || req.ID == nil {
		operatorError(w, 400, "invalid_body")
		return
	}
	r := s.op.record(*req.ID)
	if r == nil || r.actor != session.actor {
		operatorError(w, 404, "unknown_action_id")
		return
	}
	if r.State != "requested" {
		operatorError(w, 409, "not_cancellable")
		return
	}
	for _, c := range s.op.confirmations {
		if c.record == r.ID {
			delete(s.op.confirmations, c.id)
		}
	}
	s.op.transition(r, "cancelled", "withdrawn", now)
	operatorJSON(w, 200, map[string]string{"id": r.ID, "state": r.State})
}
