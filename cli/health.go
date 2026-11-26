package main

import (
	"runtime"
	"runtime/metrics"
	"strings"
	"time"
)

// Owned CLI health (roadmap 2e): a few self-measurements of this process, added to every sample under the
// reserved "cli." prefix. They are measured here, never supplied by 4D (a frame that uses the prefix is a
// schema violation) and carry no URLs, tokens, paths, identities or request data.
const ownedPrefix = "cli."

func ownedHeapBytes() float64 {
	sample := []metrics.Sample{{Name: "/memory/classes/heap/objects:bytes"}}
	metrics.Read(sample)
	if sample[0].Value.Kind() == metrics.KindUint64 {
		return float64(sample[0].Value.Uint64())
	}
	return 0
}

// ownedMetricsLocked builds the CLI's own gauges for the sample taken at `at`; the caller holds s.mu.
func (s *service) ownedMetricsLocked(at time.Time) []metric {
	gauge := func(id, label, unit string, value float64) metric {
		return metric{ID: id, Label: label, Type: "number", Unit: unit, Kind: "gauge", Availability: "available", Value: value}
	}
	uptime := at.Sub(s.mon.started).Seconds()
	if uptime < 0 {
		uptime = 0
	}
	return []metric{
		gauge("cli.uptime", "Dashboard CLI uptime", "s", float64(int64(uptime))),
		gauge("cli.goroutines", "Dashboard CLI goroutines", "goroutines", float64(runtime.NumGoroutine())),
		gauge("cli.heapBytes", "Dashboard CLI heap", "bytes", ownedHeapBytes()),
		gauge("cli.viewers", "Connected browser streams", "viewers", float64(len(s.clients))),
		gauge("cli.stdoutQueue", "Pending frames to 4D", "frames", float64(len(s.out))),
	}
}

func reservedMetric(id string) bool { return strings.HasPrefix(id, ownedPrefix) }
