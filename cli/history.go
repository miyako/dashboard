package main

import (
	"math"
	"net/http"
	"net/url"
	"time"
)

// Tiered in-memory measurement history; see docs/history.md.
const (
	rawRetention        = time.Hour
	minuteRetention     = 24 * time.Hour
	maxRawPoints        = 1800
	maxMinuteBuckets    = 1440
	maxHistorySeries    = 72
	counterGap          = 15 * time.Second
	historyRequestRate  = 240
	maxHistorySpan      = 24 * time.Hour
	maxRawHistorySpan   = time.Hour
	historyBucketLength = time.Minute
)

type rawPoint struct {
	at    time.Time
	value float64
	ok    bool
}

type minuteBucket struct {
	start                 time.Time
	count, gaps, resets   int
	min, max, sum, last   float64
	increase, incrSeconds float64
}

type series struct {
	id, label, unit, kind string
	raw                   []rawPoint
	buckets               []minuteBucket
	previous              *rawPoint
}

type maintenanceBand struct {
	from, to time.Time
	open     bool
}

const maxMaintenanceBands = 64

type history struct {
	series      map[string]*series
	newest      time.Time
	requests    []time.Time
	maintenance []maintenanceBand
}

// Maintenance bands are anonymous time spans: no action, actor or arguments.
func (h *history) openMaintenance(at time.Time) {
	h.maintenance = append(h.maintenance, maintenanceBand{from: at, open: true})
	cut := at.Add(-minuteRetention)
	keep := h.maintenance[:0]
	for _, b := range h.maintenance {
		if b.open || b.to.After(cut) {
			keep = append(keep, b)
		}
	}
	h.maintenance = keep
	if len(h.maintenance) > maxMaintenanceBands {
		h.maintenance = h.maintenance[len(h.maintenance)-maxMaintenanceBands:]
	}
}

func (h *history) closeMaintenance(at time.Time) {
	for i := range h.maintenance {
		if h.maintenance[i].open {
			h.maintenance[i].to, h.maintenance[i].open = at, false
		}
	}
}

func (h *history) maintenanceIn(from, to time.Time) []map[string]any {
	bands := []map[string]any{}
	for _, b := range h.maintenance {
		if b.from.After(to) || (!b.open && b.to.Before(from)) {
			continue
		}
		band := map[string]any{"from": stamp(b.from), "to": nil}
		if !b.open {
			band["to"] = stamp(b.to)
		}
		bands = append(bands, band)
	}
	return bands
}

func newHistory() *history { return &history{series: map[string]*series{}} }

// record adds one sample of a dynamic numeric metric; value is nil when unavailable.
func (h *history) record(m metric, at time.Time, value *float64) {
	s := h.series[m.ID]
	if s == nil {
		if len(h.series) >= maxHistorySeries {
			return
		}
		s = &series{id: m.ID}
		h.series[m.ID] = s
	}
	s.label, s.unit, s.kind = m.Label, m.Unit, m.Kind
	point := rawPoint{at: at}
	if value != nil {
		point.value, point.ok = *value, true
	}
	s.raw = append(s.raw, point)
	start := at.UTC().Truncate(historyBucketLength)
	if n := len(s.buckets); n == 0 || !s.buckets[n-1].start.Equal(start) {
		s.buckets = append(s.buckets, minuteBucket{start: start})
	}
	b := &s.buckets[len(s.buckets)-1]
	if point.ok {
		if b.count == 0 || point.value < b.min {
			b.min = point.value
		}
		if b.count == 0 || point.value > b.max {
			b.max = point.value
		}
		b.count++
		b.sum += point.value
		b.last = point.value
	} else {
		b.gaps++
	}
	if s.kind == "counter" && s.previous != nil && s.previous.ok && point.ok {
		elapsed := at.Sub(s.previous.at)
		switch {
		case point.value < s.previous.value:
			b.resets++
		case elapsed > 0 && elapsed <= counterGap:
			b.increase += point.value - s.previous.value
			b.incrSeconds += elapsed.Seconds()
		}
	}
	s.previous = &point
	if at.After(h.newest) {
		h.newest = at
	}
	h.prune(s)
}

func (h *history) prune(s *series) {
	rawCut, minuteCut := h.newest.Add(-rawRetention), h.newest.Add(-minuteRetention).Truncate(historyBucketLength)
	drop := 0
	for drop < len(s.raw) && (s.raw[drop].at.Before(rawCut) || len(s.raw)-drop > maxRawPoints) {
		drop++
	}
	// Reslice; append reallocates when capacity runs out, so memory stays within about twice the bound.
	s.raw = s.raw[drop:]
	drop = 0
	for drop < len(s.buckets) && (s.buckets[drop].start.Before(minuteCut) || len(s.buckets)-drop > maxMinuteBuckets) {
		drop++
	}
	s.buckets = s.buckets[drop:]
}

func historyError(w http.ResponseWriter, status int, code string) {
	operatorError(w, status, code)
}

func finiteOrNil(v float64, ok bool) any {
	if !ok || math.IsNaN(v) || math.IsInf(v, 0) {
		return nil
	}
	return v
}

// historyRoute serves GET /api/history; the viewer cookie was already verified.
func (s *service) historyRoute(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		historyError(w, 405, "get_required")
		return
	}
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil || len(query) != 4 {
		historyError(w, 400, "invalid_query")
		return
	}
	for _, key := range []string{"metric", "from", "to", "resolution"} {
		if len(query[key]) != 1 {
			historyError(w, 400, "invalid_query")
			return
		}
	}
	id, resolution := query.Get("metric"), query.Get("resolution")
	from, fromErr := time.Parse(time.RFC3339Nano, query.Get("from"))
	to, toErr := time.Parse(time.RFC3339Nano, query.Get("to"))
	if !identifier.MatchString(id) || fromErr != nil || toErr != nil || !from.Before(to) || to.Sub(from) > maxHistorySpan ||
		(resolution != "raw" && resolution != "minute") || (resolution == "raw" && to.Sub(from) > maxRawHistorySpan) {
		historyError(w, 400, "invalid_query")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	window := s.hist.requests[:0]
	for _, at := range s.hist.requests {
		if now.Sub(at) < time.Minute {
			window = append(window, at)
		}
	}
	s.hist.requests = window
	if len(s.hist.requests) >= historyRequestRate {
		historyError(w, 429, "rate_limited")
		return
	}
	s.hist.requests = append(s.hist.requests, now)
	series := s.hist.series[id]
	if series == nil {
		historyError(w, 404, "unknown_metric")
		return
	}
	// A series no longer reported still ages out.
	s.hist.prune(series)
	coverage := map[string]any{"rawSince": nil, "minuteSince": nil}
	if len(series.raw) > 0 {
		coverage["rawSince"] = stamp(series.raw[0].at)
	}
	if len(series.buckets) > 0 {
		coverage["minuteSince"] = stamp(series.buckets[0].start)
	}
	points := []map[string]any{}
	if resolution == "raw" {
		for _, p := range series.raw {
			if !p.at.Before(from) && !p.at.After(to) {
				points = append(points, map[string]any{"at": stamp(p.at), "value": finiteOrNil(p.value, p.ok)})
			}
		}
	} else {
		for _, b := range series.buckets {
			if b.start.Before(from.Truncate(historyBucketLength)) || b.start.After(to) {
				continue
			}
			point := map[string]any{"at": stamp(b.start), "count": b.count, "gaps": b.gaps,
				"min": finiteOrNil(b.min, b.count > 0), "max": finiteOrNil(b.max, b.count > 0),
				"mean": finiteOrNil(b.sum/math.Max(1, float64(b.count)), b.count > 0), "last": finiteOrNil(b.last, b.count > 0)}
			if series.kind == "counter" {
				point["rate"] = finiteOrNil(b.increase/b.incrSeconds, b.incrSeconds > 0)
				point["resets"] = b.resets
			}
			points = append(points, point)
		}
	}
	operatorJSON(w, 200, map[string]any{"metric": map[string]string{"id": series.id, "label": series.label, "unit": series.unit, "kind": series.kind},
		"resolution": resolution, "from": stamp(from), "to": stamp(to), "coverage": coverage, "points": points,
		"maintenance": s.hist.maintenanceIn(from, to)})
}
