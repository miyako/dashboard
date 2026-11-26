package main

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

var t0 = time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)

func f(v float64) *float64 { return &v }

func gauge(id string) metric {
	return metric{ID: id, Label: id, Type: "number", Unit: "%", Kind: "gauge", Availability: "available"}
}

func counter(id string) metric {
	return metric{ID: id, Label: id, Type: "number", Unit: "bytes", Kind: "counter", Availability: "available"}
}

func TestHistoryGaugeBucket(t *testing.T) {
	h := newHistory()
	for i, v := range []*float64{f(1), f(3), nil, f(2)} {
		h.record(gauge("g"), t0.Add(time.Duration(i)*2*time.Second), v)
	}
	b := h.series["g"].buckets
	if len(b) != 1 || b[0].count != 3 || b[0].gaps != 1 || b[0].min != 1 || b[0].max != 3 || b[0].sum != 6 || b[0].last != 2 {
		t.Fatal(b)
	}
	if raw := h.series["g"].raw; len(raw) != 4 || raw[2].ok {
		t.Fatal("unavailable sample must stay an explicit gap", raw)
	}
}

func TestHistoryCounterRateResetsAndGaps(t *testing.T) {
	h := newHistory()
	samples := []struct {
		s int
		v *float64
	}{{0, f(0)}, {2, f(10)}, {4, f(5)}, {6, f(15)}, {8, f(15)}, {28, f(30)}, {30, nil}, {32, f(40)}}
	for _, p := range samples {
		h.record(counter("c"), t0.Add(time.Duration(p.s)*time.Second), p.v)
	}
	b := h.series["c"].buckets[0]
	// 0→10 (+10/2 s), 10→5 reset, 5→15 (+10/2 s), 15→15 (+0/2 s); 28 s is a 20 s gap; 30 s unavailable breaks 32 s.
	if b.resets != 1 || b.increase != 20 || b.incrSeconds != 6 {
		t.Fatal(b)
	}
	// An increment belongs to the bucket of its later sample.
	h.record(counter("c"), t0.Add(61*time.Second), f(46))
	h.record(counter("c"), t0.Add(62*time.Second), f(50))
	next := h.series["c"].buckets[1]
	if next.increase != 4 || next.incrSeconds != 1 {
		t.Fatal("29 s gap crossed into the next bucket", next)
	}
}

func TestHistoryRetentionAndBoundsOver25Hours(t *testing.T) {
	h := newHistory()
	for i := 0; i < maxHistorySeries+1; i++ {
		h.record(gauge(fmt.Sprint("s", i)), t0, f(1))
	}
	if len(h.series) != maxHistorySeries {
		t.Fatal("series cap", len(h.series))
	}
	end := t0.Add(25 * time.Hour)
	for at := t0; !at.After(end); at = at.Add(2 * time.Second) {
		for id := range h.series {
			h.record(gauge(id), at, f(float64(at.Unix()%100)))
		}
	}
	for id, s := range h.series {
		if len(s.raw) > maxRawPoints || s.raw[0].at.Before(end.Add(-rawRetention)) || !s.raw[len(s.raw)-1].at.Equal(end) {
			t.Fatal(id, "raw", len(s.raw), s.raw[0].at)
		}
		if len(s.buckets) > maxMinuteBuckets || s.buckets[0].start.Before(end.Add(-minuteRetention).Truncate(time.Minute)) {
			t.Fatal(id, "buckets", len(s.buckets), s.buckets[0].start)
		}
		if cap(s.raw) > 4*maxRawPoints || cap(s.buckets) > 4*maxMinuteBuckets {
			t.Fatal(id, "backing arrays grew without bound", cap(s.raw), cap(s.buckets))
		}
	}
	// Faster-than-default samples (manual refreshes) are capped by count.
	fast := newHistory()
	for i := 0; i < 3600; i++ {
		fast.record(gauge("g"), t0.Add(time.Duration(i)*time.Second), f(1))
	}
	if len(fast.series["g"].raw) != maxRawPoints {
		t.Fatal(len(fast.series["g"].raw))
	}
}

func historyService(t *testing.T) *service {
	t.Helper()
	s := newService("http://127.0.0.1:8123", viewerToken)
	now := time.Now().UTC().Add(-90 * time.Second)
	h := frame("hello", 1)
	h.SampledAt = now.Format(time.RFC3339Nano)
	if err := s.apply(h); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 30; i++ {
		at := now.Add(time.Duration(i) * 2 * time.Second)
		m := frame("snapshot", uint64(i+2))
		m.SampledAt = at.Format(time.RFC3339Nano)
		value := float64(i)
		m.Metrics = []metric{
			{ID: "app.cpuUsage", Label: "CPU", Type: "number", Unit: "%", Kind: "gauge", Availability: "available", Value: value},
			{ID: "database.diskReadBytes", Label: "Read", Type: "number", Unit: "bytes", Kind: "counter", Availability: "available", Value: value * 100},
			{ID: "system.cores", Label: "Cores", Type: "number", Unit: "cores", Kind: "static", Availability: "available", Value: float64(8)},
			{ID: "app.name", Label: "Name", Type: "text", Kind: "static", Availability: "available", Value: "private"},
		}
		if i == 5 {
			m.Metrics[0] = metric{ID: "app.cpuUsage", Label: "CPU", Type: "number", Unit: "%", Kind: "gauge", Availability: "error", Reason: "failed"}
		}
		if err := s.apply(m); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func historyGet(s *service, query string, cookie bool) *httptest.ResponseRecorder {
	r := httptest.NewRequest("GET", s.origin+"/api/history?"+query, nil)
	r.Host = "127.0.0.1:8123"
	if cookie {
		r.AddCookie(&http.Cookie{Name: "dashboard", Value: s.cookie})
	}
	w := httptest.NewRecorder()
	s.handler().ServeHTTP(w, r)
	return w
}

func window(metric, resolution string, from, to time.Time) string {
	return url.Values{"metric": {metric}, "resolution": {resolution}, "from": {from.Format(time.RFC3339Nano)}, "to": {to.Format(time.RFC3339Nano)}}.Encode()
}

func TestHistoryRecordsOnlyDynamicNumbersFromFrames(t *testing.T) {
	s := historyService(t)
	if len(fromFourD(s.hist.series)) != 2 || s.hist.series["system.cores"] != nil || s.hist.series["app.name"] != nil {
		t.Fatal(len(s.hist.series))
	}
	viewer, _ := json.Marshal(s.current)
	if strings.Contains(string(viewer), "minuteSince") || len(s.current.History["app.cpuUsage"]) != 30 {
		t.Fatal("viewer state changed")
	}
}

func TestHistoryAPI(t *testing.T) {
	s := historyService(t)
	now := time.Now().UTC()
	from, to := now.Add(-time.Hour), now
	if w := historyGet(s, window("app.cpuUsage", "raw", from, to), false); w.Code != 401 {
		t.Fatal("unauthenticated history", w.Code)
	}
	w := historyGet(s, window("app.cpuUsage", "raw", from, to), true)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body)
	}
	var raw struct {
		Metric     map[string]string
		Resolution string
		Coverage   map[string]any
		Points     []map[string]any
	}
	_ = json.Unmarshal(w.Body.Bytes(), &raw)
	if len(raw.Points) != 30 || raw.Points[5]["value"] != nil || raw.Points[6]["value"] != float64(6) || raw.Metric["kind"] != "gauge" || raw.Coverage["rawSince"] == nil {
		t.Fatal(raw.Points[:7], raw.Metric, raw.Coverage)
	}
	// Window filtering: only points inside [from, to].
	var narrow struct{ Points []map[string]any }
	_ = json.Unmarshal(historyGet(s, window("app.cpuUsage", "raw", now.Add(-50*time.Second), now), true).Body.Bytes(), &narrow)
	if len(narrow.Points) == 0 || len(narrow.Points) >= 30 {
		t.Fatal("window not applied", len(narrow.Points))
	}
	w = historyGet(s, window("database.diskReadBytes", "minute", now.Add(-24*time.Hour), now), true)
	var minute struct{ Points []map[string]any }
	_ = json.Unmarshal(w.Body.Bytes(), &minute)
	total := 0.0
	for _, p := range minute.Points {
		total += p["count"].(float64)
		if p["rate"] != nil && math.Abs(p["rate"].(float64)-50) > 1e-9 {
			t.Fatal("counter rate is not elapsed-time based", p)
		}
		if _, ok := p["resets"]; !ok {
			t.Fatal("counter bucket without resets", p)
		}
	}
	if total != 30 || len(minute.Points) == 0 || len(minute.Points) > 3 {
		t.Fatal(minute.Points)
	}
	var gaugeMinute struct{ Points []map[string]any }
	_ = json.Unmarshal(historyGet(s, window("app.cpuUsage", "minute", now.Add(-time.Hour), now), true).Body.Bytes(), &gaugeMinute)
	if _, ok := gaugeMinute.Points[0]["rate"]; ok || gaugeMinute.Points[0]["gaps"] == nil {
		t.Fatal("gauge bucket carries a rate")
	}
	base := window("app.cpuUsage", "raw", from, to)
	for name, test := range map[string]struct {
		query  string
		status int
	}{
		"missing":       {"metric=app.cpuUsage&resolution=raw", 400},
		"extra":         {base + "&format=csv", 400},
		"duplicate":     {base + "&metric=app.cpuUsage", 400},
		"bad time":      {strings.Replace(base, "from=", "from=yesterday", 1), 400},
		"reversed":      {window("app.cpuUsage", "raw", to, from), 400},
		"raw too long":  {window("app.cpuUsage", "raw", now.Add(-2*time.Hour), now), 400},
		"span too long": {window("app.cpuUsage", "minute", now.Add(-25*time.Hour), now), 400},
		"resolution":    {window("app.cpuUsage", "hour", from, to), 400},
		"bad id":        {window("../etc", "raw", from, to), 400},
		"unknown":       {window("app.unknown", "raw", from, to), 404},
		"static":        {window("system.cores", "raw", from, to), 404},
	} {
		if w := historyGet(s, test.query, true); w.Code != test.status {
			t.Fatalf("%s: %d %s", name, w.Code, w.Body)
		}
	}
	r := httptest.NewRequest("POST", s.origin+"/api/history?"+base, nil)
	r.Host = "127.0.0.1:8123"
	r.AddCookie(&http.Cookie{Name: "dashboard", Value: s.cookie})
	post := httptest.NewRecorder()
	s.handler().ServeHTTP(post, r)
	if post.Code != 405 {
		t.Fatal("POST history", post.Code)
	}
	s.hist.requests = nil
	for i := 0; i < historyRequestRate; i++ {
		historyGet(s, base, true)
	}
	if w := historyGet(s, base, true); w.Code != 429 {
		t.Fatal("rate limit", w.Code)
	}
}
