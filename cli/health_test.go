package main

import (
	"strings"
	"testing"
	"time"
)

// fromFourD returns the entries of an ID-keyed map that did not come from the CLI itself.
func fromFourD[V any](m map[string]V) map[string]V {
	out := map[string]V{}
	for id, v := range m {
		if !reservedMetric(id) {
			out[id] = v
		}
	}
	return out
}

func healthService(t *testing.T) *service {
	t.Helper()
	s := newService("e", "t")
	if err := s.apply(message{Protocol: 1, Kind: "hello", Epoch: "e1", Seq: 1, SampledAt: time.Now().UTC().Format(time.RFC3339Nano)}); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestOwnedHealthMetricsAreValidAndRideEverySample(t *testing.T) {
	s := healthService(t)
	if err := s.apply(message{Protocol: 1, Kind: "snapshot", Epoch: "e1", Seq: 2, SampledAt: time.Now().UTC().Format(time.RFC3339Nano)}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"cli.uptime", "cli.goroutines", "cli.heapBytes", "cli.viewers", "cli.stdoutQueue"} {
		m, ok := s.current.Metrics[id]
		if !ok || !validMetric(m) || m.Availability != "available" || m.Kind != "gauge" || m.Type != "number" {
			t.Fatalf("%s missing or invalid: %+v", id, m)
		}
		if len(s.current.History[id]) != 1 {
			t.Fatalf("%s not graphed", id)
		}
	}
	if v := s.current.Metrics["cli.goroutines"].Value.(float64); v < 1 {
		t.Fatalf("goroutines %v", v)
	}
	if v := s.current.Metrics["cli.heapBytes"].Value.(float64); v <= 0 {
		t.Fatalf("heap %v", v)
	}
	// An update keeps them, and a delete from 4D cannot remove them.
	update := message{Protocol: 1, Kind: "update", Epoch: "e1", Seq: 3, SampledAt: time.Now().UTC().Format(time.RFC3339Nano),
		Delete: &deletions{Metrics: []string{"cli.uptime"}}}
	if err := s.apply(update); err != nil {
		t.Fatal(err)
	}
	if _, ok := s.current.Metrics["cli.uptime"]; !ok {
		t.Fatal("4D deleted an owned metric")
	}
}

func TestFourDCannotSupplyReservedMetrics(t *testing.T) {
	s := healthService(t)
	forged := metric{ID: "cli.uptime", Label: "forged", Type: "number", Unit: "s", Kind: "gauge", Availability: "available", Value: float64(1)}
	err := s.apply(message{Protocol: 1, Kind: "snapshot", Epoch: "e1", Seq: 2, SampledAt: time.Now().UTC().Format(time.RFC3339Nano), Metrics: []metric{forged}})
	if err == nil || !strings.Contains(err.Error(), "schema") {
		t.Fatalf("accepted a reserved metric: %v", err)
	}
}

func TestOwnedHealthCarriesNoPrivateData(t *testing.T) {
	s := healthService(t)
	for _, m := range s.ownedMetricsLocked(time.Now()) {
		text := m.ID + m.Label + m.Unit
		for _, secret := range []string{"http", "/", "token", "epoch"} {
			if secret != "" && strings.Contains(strings.ToLower(text), strings.ToLower(secret)) {
				t.Fatalf("%s mentions %q", m.ID, secret)
			}
		}
	}
}
