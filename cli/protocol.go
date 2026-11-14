package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const maxFrame = 256 * 1024

var identifier = regexp.MustCompile(`^[A-Za-z0-9_.:-]{1,96}$`)
var errBusy = errors.New("refresh already pending or rate limited")

type metric struct {
	ID           string `json:"id"`
	Label        string `json:"label"`
	Type         string `json:"type"`
	Unit         string `json:"unit"`
	Kind         string `json:"kind"`
	Availability string `json:"availability"`
	Value        any    `json:"value,omitempty"`
	Reason       string `json:"reason,omitempty"`
}

type entity struct {
	ID    string   `json:"id"`
	State string   `json:"state"`
	Type  string   `json:"type"`
	CPU   *float64 `json:"cpu,omitempty"`
}

type message struct {
	Protocol  int               `json:"protocol"`
	Kind      string            `json:"kind"`
	Epoch     string            `json:"epoch"`
	Seq       uint64            `json:"seq"`
	SampledAt string            `json:"sampledAt"`
	Info      map[string]string `json:"info,omitempty"`
	Metrics   []metric          `json:"metrics,omitempty"`
	Processes []entity          `json:"processes,omitempty"`
	Sessions  []entity          `json:"sessions,omitempty"`
	Delete    *deletions        `json:"delete,omitempty"`
	ID        string            `json:"id,omitempty"`
	OK        *bool             `json:"ok,omitempty"`
	Error     string            `json:"error,omitempty"`
}

type deletions struct {
	Metrics   []string `json:"metrics"`
	Processes []string `json:"processes"`
	Sessions  []string `json:"sessions"`
}

type point struct {
	At    string   `json:"at"`
	Value *float64 `json:"value"`
}

type activityEntity struct {
	State string   `json:"state"`
	CPU   *float64 `json:"cpu,omitempty"`
}

type activity struct {
	Entities map[string]activityEntity `json:"entities"`
}

type activitySample struct {
	At        string   `json:"at"`
	Processes activity `json:"processes"`
	Sessions  activity `json:"sessions"`
}

type state struct {
	Epoch      string             `json:"epoch"`
	Seq        uint64             `json:"seq"`
	SampledAt  string             `json:"sampledAt"`
	Status     string             `json:"status"`
	Info       map[string]string  `json:"info"`
	Metrics    map[string]metric  `json:"metrics"`
	Processes  map[string]entity  `json:"processes"`
	Sessions   map[string]entity  `json:"sessions"`
	History    map[string][]point `json:"history"`
	Activity   []activitySample   `json:"activity"`
	LastAction any                `json:"lastAction,omitempty"`
}

type service struct {
	mu                    sync.Mutex
	origin, token, cookie string
	current               state
	last                  time.Time
	lastRequest           time.Time
	pending               string
	requestAt             time.Time
	expired               []string
	out                   chan any
	clients               map[chan []byte]bool
}

func newService(origin, token string) *service {
	return &service{origin: origin, token: token, cookie: nonce(), out: make(chan any, 64), clients: make(map[chan []byte]bool),
		current: state{Status: "waiting", Info: map[string]string{}, Metrics: map[string]metric{}, Processes: map[string]entity{}, Sessions: map[string]entity{}, History: map[string][]point{}}}
}

func (s *service) emit(v any) error {
	select {
	case s.out <- v:
		return nil
	default:
		return errors.New("stdout queue exhausted; owner is not consuming events")
	}
}

func (s *service) initialized() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.current.Epoch != ""
}

func (s *service) read(input io.Reader) error {
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), maxFrame+1)
	scanner.Split(func(data []byte, eof bool) (int, []byte, error) {
		if index := bytes.IndexByte(data, '\n'); index >= 0 {
			return index + 1, data[:index], nil
		}
		if eof && len(data) > 0 {
			return 0, nil, errors.New("incomplete NDJSON frame at EOF")
		}
		return 0, nil, nil
	})
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) > maxFrame || !utf8.Valid(line) {
			return errors.New("invalid UTF-8 or oversized stdin frame")
		}
		var m message
		decoder := json.NewDecoder(bytes.NewReader(line))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&m); err != nil {
			return fmt.Errorf("stdin frame: %w", err)
		}
		if err := decoder.Decode(new(any)); err != io.EOF {
			return errors.New("stdin frame must contain exactly one JSON object")
		}
		if err := s.apply(m); err != nil {
			return err
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("stdin framing: %w", err)
	}
	// EOF deliberately shuts down the web server with the owning 4D instance.
	return nil
}

func validMetric(m metric) bool {
	if !identifier.MatchString(m.ID) || m.Label == "" || len(m.Label) > 120 || len(m.Unit) > 24 ||
		(m.Kind != "gauge" && m.Kind != "counter" && m.Kind != "static") {
		return false
	}
	if m.Type != "number" && m.Type != "text" && m.Type != "boolean" {
		return false
	}
	if strings.HasPrefix(m.ID, "backup.") && !validBackupMetric(m) {
		return false
	}
	switch m.Availability {
	case "available":
		switch m.Type {
		case "number":
			v, ok := m.Value.(float64)
			if !ok || math.IsNaN(v) || math.IsInf(v, 0) {
				return false
			}
			if m.Unit == "records" {
				return v >= 0 && v <= 9007199254740991 && math.Trunc(v) == v
			}
			if m.Unit == "dataclasses" || m.Unit == "tables" {
				return v >= 0 && v <= 512 && math.Trunc(v) == v
			}
			return true
		case "text":
			v, ok := m.Value.(string)
			return ok && len(v) <= 512
		case "boolean":
			_, ok := m.Value.(bool)
			return ok
		}
	case "unsupported", "missing", "error":
		return m.Value == nil && m.Reason != "" && len(m.Reason) <= 256
	}
	return false
}

func validBackupMetric(m metric) bool {
	if m.Kind != "static" {
		return false
	}
	switch m.ID {
	case "backup.statusCode", "backup.duration":
		unit := ""
		if m.ID == "backup.duration" {
			unit = "ms"
		}
		if m.Type != "number" || m.Unit != unit {
			return false
		}
		if m.Availability == "available" {
			value, ok := m.Value.(float64)
			minimum := float64(-2147483648)
			if m.ID == "backup.duration" {
				minimum = 0
			}
			return ok && value >= minimum && value <= 2147483647 && math.Trunc(value) == value
		}
	case "backup.lastAt", "backup.nextAt", "backup.beginUTC", "backup.observedAt":
		if m.Type != "text" || m.Unit != "" {
			return false
		}
		if m.Availability == "available" {
			value, ok := m.Value.(string)
			if !ok {
				return false
			}
			layout := "2006-01-02T15:04:05"
			if m.ID == "backup.beginUTC" || m.ID == "backup.observedAt" {
				layout += ".000Z"
			}
			parsed, err := time.Parse(layout, value)
			return err == nil && parsed.Year() > 0 && parsed.Format(layout) == value
		}
	default:
		return false
	}
	return true
}

func validEntities(items []entity) bool {
	seen := map[string]bool{}
	for _, e := range items {
		if !identifier.MatchString(e.ID) || seen[e.ID] || len(e.State) > 64 || len(e.Type) > 64 {
			return false
		}
		if e.CPU != nil && (*e.CPU < 0 || *e.CPU > 1 || math.IsNaN(*e.CPU)) {
			return false
		}
		seen[e.ID] = true
	}
	return true
}

func (s *service) apply(m message) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if m.Protocol != 1 || !identifier.MatchString(m.Epoch) || m.Seq == 0 || m.Seq > 9007199254740991 {
		return errors.New("invalid protocol, epoch or sequence")
	}
	if m.Kind == "hello" {
		if s.current.Epoch != "" || m.Seq != 1 || len(m.Info) > 16 {
			return errors.New("hello must be the first frame with seq 1")
		}
		for k, v := range m.Info {
			if !identifier.MatchString(k) || len(v) > 256 {
				return errors.New("invalid instance information")
			}
		}
	} else if s.current.Epoch == "" || m.Epoch != s.current.Epoch || m.Seq != s.current.Seq+1 {
		return errors.New("epoch or sequence mismatch; restart the CLI and send a fresh hello")
	}
	at, err := time.Parse(time.RFC3339Nano, m.SampledAt)
	if err != nil || at.After(time.Now().Add(time.Minute)) {
		return errors.New("invalid sample timestamp")
	}
	if !s.last.IsZero() {
		previous, _ := time.Parse(time.RFC3339Nano, s.current.SampledAt)
		if at.Before(previous) {
			return errors.New("sample timestamp moved backwards")
		}
	}
	switch m.Kind {
	case "hello":
		s.current.Epoch, s.current.Info = m.Epoch, m.Info
	case "snapshot", "update":
		if len(m.Metrics) > 256 || len(m.Processes) > 512 || len(m.Sessions) > 512 ||
			!validEntities(m.Processes) || !validEntities(m.Sessions) {
			return errors.New("entity limit or schema violation")
		}
		seen := map[string]bool{}
		for _, v := range m.Metrics {
			if !validMetric(v) || seen[v.ID] {
				return errors.New("metric schema violation")
			}
			seen[v.ID] = true
		}
		// Validate the resulting sizes before mutating any state.
		metrics, processes, sessions := map[string]metric{}, map[string]entity{}, map[string]entity{}
		if m.Kind == "update" {
			for k, v := range s.current.Metrics {
				metrics[k] = v
			}
			for k, v := range s.current.Processes {
				processes[k] = v
			}
			for k, v := range s.current.Sessions {
				sessions[k] = v
			}
		}
		for _, v := range m.Metrics {
			metrics[v.ID] = v
		}
		for _, v := range m.Processes {
			processes[v.ID] = v
		}
		for _, v := range m.Sessions {
			sessions[v.ID] = v
		}
		if m.Delete != nil {
			for _, k := range m.Delete.Metrics {
				delete(metrics, k)
			}
			for _, k := range m.Delete.Processes {
				delete(processes, k)
			}
			for _, k := range m.Delete.Sessions {
				delete(sessions, k)
			}
		}
		if len(metrics) > 256 || len(processes) > 512 || len(sessions) > 512 {
			return errors.New("resulting state exceeds capacity")
		}
		for k := range s.current.History {
			if _, exists := metrics[k]; !exists {
				delete(s.current.History, k)
			}
		}
		for _, v := range m.Metrics {
			if _, exists := metrics[v.ID]; !exists {
				continue
			}
			if v.Type == "number" && v.Kind != "static" {
				var value *float64
				if v.Availability == "available" {
					n := v.Value.(float64)
					value = &n
				}
				h := append(s.current.History[v.ID], point{m.SampledAt, value})
				if len(h) > 60 {
					h = h[len(h)-60:]
				}
				s.current.History[v.ID] = h
			} else {
				delete(s.current.History, v.ID)
			}
		}
		s.current.Metrics, s.current.Processes, s.current.Sessions = metrics, processes, sessions
		s.current.Activity = append(s.current.Activity, activitySample{
			At: m.SampledAt, Processes: sampleActivity(processes, metrics["process.count"]),
			Sessions: sampleActivity(sessions, metrics["session.count"]),
		})
		if len(s.current.Activity) > 60 {
			s.current.Activity = s.current.Activity[len(s.current.Activity)-60:]
		}
	case "result":
		if m.ID == "" || m.OK == nil || (!*m.OK && m.Error == "") || len(m.Error) > 256 {
			return errors.New("uncorrelated or invalid action result")
		}
		if m.ID == s.pending {
			s.pending = ""
			s.current.LastAction = map[string]any{"id": m.ID, "ok": *m.OK, "error": m.Error}
		} else {
			index := -1
			for i, id := range s.expired {
				if id == m.ID {
					index = i
					break
				}
			}
			if index < 0 {
				return errors.New("uncorrelated or replayed action result")
			}
			s.expired = append(s.expired[:index], s.expired[index+1:]...)
			// A late result consumes its sequence but never replays a timed-out action.
		}
	default:
		return errors.New("unsupported message kind")
	}
	s.current.Seq, s.current.SampledAt = m.Seq, m.SampledAt
	s.last, s.current.Status = time.Now(), "connected"
	s.broadcastLocked()
	return nil
}

func sampleActivity(entities map[string]entity, count metric) activity {
	result := activity{}
	// A failed enumeration must not look like a known empty list.
	if (count.ID != "" && count.Availability != "available") || (count.ID == "" && len(entities) == 0) {
		return result
	}
	result.Entities = make(map[string]activityEntity, len(entities))
	for id, e := range entities {
		result.Entities[id] = activityEntity{State: e.State, CPU: e.CPU}
	}
	return result
}

func (s *service) broadcastLocked() {
	body, _ := json.Marshal(s.current)
	for client := range s.clients {
		select {
		case <-client:
		default:
		}
		client <- body
	}
}

func (s *service) request() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.current.Epoch == "" || s.pending != "" || time.Since(s.lastRequest) < time.Second {
		return "", errBusy
	}
	id := nonce()
	if err := s.emit(map[string]any{"protocol": 1, "kind": "request", "epoch": s.current.Epoch, "id": id, "action": "refresh"}); err != nil {
		return "", err
	}
	s.pending, s.requestAt, s.lastRequest = id, time.Now(), time.Now()
	return id, nil
}

func (s *service) expire() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pending != "" && time.Since(s.requestAt) > 10*time.Second {
		s.current.LastAction = map[string]any{"id": s.pending, "ok": false, "error": "collector_timeout"}
		s.expired = append(s.expired, s.pending)
		if len(s.expired) > 32 {
			s.expired = s.expired[len(s.expired)-32:]
		}
		s.pending = ""
		s.broadcastLocked()
	}
	if !s.last.IsZero() && time.Since(s.last) > 15*time.Second && s.current.Status != "stale" {
		s.current.Status = "stale"
		s.broadcastLocked()
	}
}
