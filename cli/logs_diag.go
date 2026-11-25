package main

import (
	"bytes"
	"errors"
	"io"
	"os"
	"regexp"
	"time"
)

// Log browsing L2 (docs/log-browsing-design.md): the 4D diagnostic log's parsed columns. A level filter and a jump
// to a host-local time work only on families whose catalog entry says `"parse": "diagnostic"`.
//
// The line grammar was observed on tool4d 21.1 and full 4D 21.2 (`seq time [component] LEVEL - message`).
// Only ERROR has been observed in real files; the other level names follow 4D's documentation and are unconfirmed.

const (
	maxFilterScan = 8 << 20   // bytes examined by one filtered page or time search
	filterChunk   = 200       // lines examined per step of a filtered scan
	backBlock     = 256 << 10 // bytes read per step of a backward scan
	timeWindow    = 64 << 10  // the binary search stops narrowing below this
	timeProbeSkip = 64        // unparsable lines skipped when probing for a timestamp
)

var errScanCancelled = errors.New("cancelled")

var diagnosticLevels = map[string]bool{"ERROR": true, "WARN": true, "INFO": true, "DEBUG": true, "TRACE": true}

var diagnosticLine = regexp.MustCompile(`^[0-9]+ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?) \[[^\]\n]*\] ([A-Z]+) - `)
var timeInput = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,3})?)?$`)

// normalizeStamp pads a timestamp to YYYY-MM-DDTHH:MM:SS.mmm so plain string comparison orders it, and
// rejects impossible dates. The values carry no time zone: they are the host's local time.
func normalizeStamp(text string) (string, bool) {
	switch len(text) {
	case 16: // HH:MM
		text += ":00.000"
	case 19:
		text += ".000"
	case 21:
		text += "00"
	case 22:
		text += "0"
	case 23:
	default:
		return "", false
	}
	if _, err := time.Parse("2006-01-02T15:04:05.000", text); err != nil {
		return "", false
	}
	return text, true
}

// parseDiagnostic returns the normalized timestamp and the level of a diagnostic line.
func parseDiagnostic(text string) (stamp, level string, ok bool) {
	m := diagnosticLine.FindStringSubmatch(text)
	if m == nil {
		return "", "", false
	}
	stamp, ok = normalizeStamp(m[1])
	return stamp, m[2], ok
}

func levelMatcher(level string) func(string) bool {
	return func(text string) bool {
		_, l, ok := parseDiagnostic(text)
		return ok && l == level
	}
}

func reverseLines(lines []logLine) {
	for i, j := 0, len(lines)-1; i < j; i, j = i+1, j-1 {
		lines[i], lines[j] = lines[j], lines[i]
	}
}

// readFilteredForward returns up to limit matching lines from a line start. next is where a continuation
// starts; limited reports that the scan budget ended the scan before the file or the limit did.
func readFilteredForward(f *os.File, from, end int64, limit int, match func(string) bool, budget int64, stop func() bool) (lines []logLine, next int64, limited bool, err error) {
	lines = []logLine{}
	pos := from
	for pos < end {
		if stop != nil && stop() {
			return nil, 0, false, errScanCancelled
		}
		if pos-from >= budget {
			return lines, pos, true, nil
		}
		chunk, chunkEnd, err := readForward(f, pos, end, filterChunk)
		if err != nil {
			return nil, 0, false, err
		}
		if chunkEnd <= pos {
			break
		}
		for i, line := range chunk {
			after := chunkEnd
			if i+1 < len(chunk) {
				after = chunk[i+1].offset
			}
			if match(line.Text) {
				lines = append(lines, line)
				if len(lines) == limit {
					return lines, after, false, nil
				}
			}
		}
		pos = chunkEnd
	}
	return lines, pos, false, nil
}

// backwardBlock returns the complete lines in the block that ends at a line start, oldest first, and the
// offset of the first of them (the next boundary).
func backwardBlock(f *os.File, before int64) ([]logLine, int64, error) {
	start := before - backBlock
	if start < 0 {
		start = 0
	}
	buf := make([]byte, before-start)
	n, err := f.ReadAt(buf, start)
	if err != nil && err != io.EOF {
		return nil, 0, err
	}
	buf = buf[:n]
	first := int64(0)
	if start > 0 {
		i := bytes.IndexByte(buf, '\n')
		if i < 0 {
			return nil, 0, errors.New("line_too_long")
		}
		first = int64(i) + 1
	}
	lines := []logLine{}
	offset := start + first
	for _, raw := range bytes.Split(buf[first:], []byte{'\n'}) {
		// The block ends at a line start, so the last element is the empty remainder.
		if offset >= start+int64(len(buf)) {
			break
		}
		text, truncated := lineText(raw)
		lines = append(lines, logLine{Text: text, Truncated: truncated, offset: offset})
		offset += int64(len(raw)) + 1
	}
	return lines, start + first, nil
}

// readFilteredBackward returns up to limit matching lines that end before a line start, oldest first.
func readFilteredBackward(f *os.File, before int64, limit int, match func(string) bool, budget int64, stop func() bool) (lines []logLine, newBefore int64, limited bool, err error) {
	collected := []logLine{}
	pos := before
	for pos > 0 {
		if stop != nil && stop() {
			return nil, 0, false, errScanCancelled
		}
		if before-pos >= budget {
			reverseLines(collected)
			return collected, pos, true, nil
		}
		chunk, boundary, err := backwardBlock(f, pos)
		if err != nil {
			return nil, 0, false, err
		}
		if boundary >= pos {
			break
		}
		for i := len(chunk) - 1; i >= 0; i-- {
			if match(chunk[i].Text) {
				collected = append(collected, chunk[i])
				if len(collected) == limit {
					reverseLines(collected)
					return collected, chunk[i].offset, false, nil
				}
			}
		}
		pos = boundary
	}
	reverseLines(collected)
	return collected, pos, false, nil
}

// lineStartAtOrAfter returns the first line start at or after pos, or limit when none begins before it.
func lineStartAtOrAfter(f *os.File, pos, limit int64) (int64, error) {
	if pos <= 0 {
		return 0, nil
	}
	prev := make([]byte, 1)
	if _, err := f.ReadAt(prev, pos-1); err != nil {
		return 0, err
	}
	if prev[0] == '\n' {
		return pos, nil
	}
	next, err := skipToNewline(f, pos, limit)
	if err != nil {
		if err.Error() == "line_too_long" {
			return limit, nil
		}
		return 0, err
	}
	return next, nil
}

// probeStamp finds the first timestamped line within a few lines of a line start; after is where a probe that
// found nothing may continue.
func probeStamp(f *os.File, pos, end int64) (offset int64, stamp string, next int64, found bool, err error) {
	lines, after, err := readForward(f, pos, end, timeProbeSkip)
	if err != nil {
		return 0, "", 0, false, err
	}
	for i, line := range lines {
		if s, _, ok := parseDiagnostic(line.Text); ok {
			next = after
			if i+1 < len(lines) {
				next = lines[i+1].offset
			}
			return line.offset, s, next, true, nil
		}
	}
	return 0, "", after, false, nil
}

// findTime returns the start of the first line at or after target (normalized host-local time), or end when
// every line is earlier. It assumes timestamps never go backwards in the file, which 4D's append-only log
// satisfies except across a host clock change: then the result is the nearest the search can reach.
func findTime(f *os.File, end int64, target string) (int64, error) {
	lo, hi := int64(0), end
	for i := 0; hi-lo > timeWindow && i < 64; i++ {
		mid := lo + (hi-lo)/2
		s, err := lineStartAtOrAfter(f, mid, hi)
		if err != nil {
			return 0, err
		}
		if s >= hi {
			break // one very long line spans the rest: the linear step below is bounded
		}
		offset, stamp, next, found, err := probeStamp(f, s, end)
		if err != nil {
			return 0, err
		}
		switch {
		case !found:
			lo = min(next, hi)
		case stamp < target:
			lo = min(next, hi)
		default:
			hi = offset
		}
	}
	pos := lo
	for pos < hi && pos-lo < maxFilterScan {
		lines, after, err := readForward(f, pos, hi, filterChunk)
		if err != nil {
			return 0, err
		}
		if after <= pos {
			break
		}
		for _, line := range lines {
			if s, _, ok := parseDiagnostic(line.Text); ok && s >= target {
				return line.offset, nil
			}
		}
		pos = after
	}
	return min(pos, hi), nil
}
