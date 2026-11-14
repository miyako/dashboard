package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"time"
)

// M4 monitor controls: owner-approved sampling cadence and sanitized diagnostics.
// Both run through the operator pipeline; Go applies them only after 4D reports completed.

const defaultCadence = 2 * time.Second
const maxObservedIntervals = 8

// allowedCadences never goes faster than the default, so collector load cannot rise.
var allowedCadences = map[int]bool{2: true, 5: true, 10: true}

type monitorState struct {
	cadence          time.Duration
	cadenceSince     time.Time
	started          time.Time
	scheduled        []time.Time
	cadenceCh        chan time.Duration
	scheduledCount   uint64
	busySkips        uint64
	refreshResults   uint64
	refreshTimeouts  uint64
	lateRefreshCount uint64
	collectorBusy    uint64
	paused           bool
	pauses           uint64
	pausedSkips      uint64
}

func newMonitorState() monitorState {
	now := time.Now()
	return monitorState{cadence: defaultCadence, cadenceSince: now, started: now, cadenceCh: make(chan time.Duration, 1)}
}

// setCadenceLocked records the new cadence and hands it to the scheduler, replacing any unread change.
func (s *service) setCadenceLocked(d time.Duration, now time.Time) {
	s.mon.cadence, s.mon.cadenceSince, s.mon.scheduled = d, now, nil
	select {
	case <-s.mon.cadenceCh:
	default:
	}
	s.mon.cadenceCh <- d
}

func (s *service) observedIntervalsLocked() []int64 {
	intervals := []int64{}
	for i := 1; i < len(s.mon.scheduled); i++ {
		intervals = append(intervals, s.mon.scheduled[i].Sub(s.mon.scheduled[i-1]).Milliseconds())
	}
	return intervals
}

func (s *service) cadenceLocked() map[string]any {
	return map[string]any{"seconds": int(s.mon.cadence / time.Second), "since": stamp(s.mon.cadenceSince),
		"observedIntervalsMs": s.observedIntervalsLocked()}
}

// diagnosticsLocked returns owned, sanitized counters only: no URLs, tokens, epochs, IDs or arguments.
func (s *service) diagnosticsLocked(now time.Time) map[string]any {
	states := map[string]int{}
	for _, r := range s.op.records {
		states[r.State]++
	}
	lastSampleAge := int64(-1)
	if !s.last.IsZero() {
		lastSampleAge = now.Sub(s.last).Milliseconds()
	}
	return map[string]any{
		"version": version, "uptimeSeconds": int64(now.Sub(s.mon.started).Seconds()), "stream": s.current.Status,
		"lastFrameAgeMs": lastSampleAge, "cadence": s.cadenceLocked(),
		"scheduledRequests": s.mon.scheduledCount, "scheduledBusySkips": s.mon.busySkips,
		"refreshResults": s.mon.refreshResults, "refreshTimeouts": s.mon.refreshTimeouts, "lateRefreshResults": s.mon.lateRefreshCount,
		"viewers": len(s.clients), "stdoutQueue": len(s.out), "stdoutCapacity": cap(s.out),
		"metrics": len(s.current.Metrics), "processes": len(s.current.Processes), "sessions": len(s.current.Sessions),
		"operatorSessions": len(s.op.sessions), "pendingConfirmations": len(s.op.confirmations),
		"collectorBusy": s.mon.collectorBusy, "paused": s.mon.paused, "maintenancePauses": s.mon.pauses, "pausedSkips": s.mon.pausedSkips,
		"actionStates": states, "lateActionFrames": s.op.late,
	}
}

// applyCompletedLocked runs the Go half of a monitor action after 4D approved and audited it.
func (s *service) applyCompletedLocked(r *actionRecord, now time.Time) {
	switch r.Action {
	case "monitor.cadence":
		var args struct {
			Seconds int `json:"seconds"`
		}
		if json.Unmarshal(r.args, &args) == nil && allowedCadences[args.Seconds] {
			s.setCadenceLocked(time.Duration(args.Seconds)*time.Second, now)
			r.Result = map[string]any{"seconds": args.Seconds, "appliedAt": stamp(now)}
		}
	case "monitor.diagnostics":
		r.Result = s.diagnosticsLocked(now)
	}
}

// pauseLocked suspends scheduled sampling for an exclusive action and opens a maintenance band.
func (s *service) pauseLocked(now time.Time) {
	if s.mon.paused {
		return
	}
	s.mon.paused, s.current.Status = true, "maintenance"
	s.mon.pauses++
	s.hist.openMaintenance(now)
	s.broadcastLocked()
}

// settleLocked resumes sampling once no action is in flight.
func (s *service) settleLocked(now time.Time) {
	if !s.mon.paused || (s.op != nil && s.op.inflight != nil) {
		return
	}
	s.mon.paused = false
	s.hist.closeMaintenance(now)
	s.current.Status = "connected"
	if !s.last.IsZero() && now.Sub(s.last) > 15*time.Second {
		s.current.Status = "stale"
	}
	s.broadcastLocked()
}

func (s *service) secureOrLoopback() bool {
	if strings.HasPrefix(s.origin, "https://") {
		return true
	}
	host, _, err := net.SplitHostPort(strings.TrimPrefix(s.origin, "http://"))
	ip := net.ParseIP(strings.Trim(host, "[]"))
	return err == nil && ip != nil && ip.IsLoopback()
}

func (s *service) scheduledRequest(now time.Time) error {
	s.mu.Lock()
	paused := s.mon.paused
	if paused {
		s.mon.pausedSkips++
	}
	s.mu.Unlock()
	if paused {
		return nil
	}
	if _, err := s.request(); err != nil {
		if errors.Is(err, errBusy) {
			s.mu.Lock()
			s.mon.busySkips++
			s.mu.Unlock()
			return nil
		}
		return err
	}
	s.mu.Lock()
	s.mon.scheduledCount++
	s.mon.scheduled = append(s.mon.scheduled, now)
	if len(s.mon.scheduled) > maxObservedIntervals+1 {
		s.mon.scheduled = s.mon.scheduled[len(s.mon.scheduled)-maxObservedIntervals-1:]
	}
	s.mu.Unlock()
	return nil
}

// schedule is the real sampling scheduler: housekeeping every second, sampling at the current cadence.
func (s *service) schedule(ctx context.Context, failures <-chan error) error {
	s.mu.Lock()
	cadence := s.mon.cadence
	s.mu.Unlock()
	ticker := time.NewTicker(cadence)
	defer ticker.Stop()
	housekeeping := time.NewTicker(time.Second)
	defer housekeeping.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case err := <-failures:
			return err
		case d := <-s.mon.cadenceCh:
			ticker.Reset(d)
		case <-housekeeping.C:
			s.expire()
		case at := <-ticker.C:
			if s.initialized() {
				if err := s.scheduledRequest(at); err != nil {
					return err
				}
			}
		}
	}
}
