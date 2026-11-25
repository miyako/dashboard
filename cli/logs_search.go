package main

import (
	"crypto/hmac"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"
)

// Log browsing L3 (docs/log-browsing-design.md): plain-substring search inside an opened view. Every search
// request is authorized and audited by 4D first (fail-closed, like an open); the audit records only a keyed
// digest of the text, never the text. No regular expressions, no export.

const (
	searchScanBudget = 64 << 20 // bytes examined per request; a continuation cursor resumes
	maxSearchMatches = 200
	maxSearchText    = 128
	searchRate       = 30 // requests per minute and operator session
)

// searchDigest is the keyed digest of a query that reaches 4D (and so the audit): stable within one CLI run,
// useless without the run's key, and never the text itself.
func (l *logsConfig) searchDigest(text string, insensitive bool) string {
	flag := "s"
	if insensitive {
		flag = "i"
	}
	return l.mac("search", flag, text)[:16]
}

func validSearchText(text string) bool {
	if len(text) < 1 || len(text) > maxSearchText || !utf8.ValidString(text) {
		return false
	}
	for _, r := range text {
		if r < 0x20 || r == 0x7f {
			return false
		}
	}
	return true
}

func (s *service) logsSearch(w http.ResponseWriter, r *http.Request, body []byte, logs *logsConfig, actor string) {
	var req struct {
		View            *string `json:"view"`
		Text            *string `json:"text"`
		CaseInsensitive *bool   `json:"caseInsensitive"`
		Direction       *string `json:"direction"`
		From            *string `json:"from"`
	}
	if strictDecode(body, &req) != nil || req.View == nil || req.Text == nil || req.CaseInsensitive == nil ||
		req.Direction == nil || req.From == nil || (*req.Direction != "forward" && *req.Direction != "backward") ||
		!validSearchText(*req.Text) {
		logError(w, 400, "invalid_body")
		return
	}
	s.mu.Lock()
	view := logs.views[actor]
	if view == nil || !hmac.Equal([]byte(view.token), []byte(*req.View)) {
		s.mu.Unlock()
		logError(w, 404, "unknown_view")
		return
	}
	var offset int64 = -1
	switch *req.From {
	case "start":
		offset = 0
	case "end":
	default:
		var ok bool
		if offset, ok = logs.parseCursor(view.token, *req.From); !ok {
			s.mu.Unlock()
			logError(w, 400, errInvalidCursor)
			return
		}
	}
	if logs.searching[actor] {
		s.mu.Unlock()
		logError(w, 429, "search_pending")
		return
	}
	now := time.Now()
	window := logs.searches[actor][:0]
	for _, at := range logs.searches[actor] {
		if now.Sub(at) < time.Minute {
			window = append(window, at)
		}
	}
	if len(window) >= searchRate {
		logs.searches[actor] = window
		s.mu.Unlock()
		logError(w, 429, "rate_limited")
		return
	}
	logs.searches[actor] = append(window, now)
	logs.searching[actor] = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(logs.searching, actor)
		s.mu.Unlock()
	}()
	digest := logs.searchDigest(*req.Text, *req.CaseInsensitive)
	if status, code := s.logAuthorize(logs, actor, "search", logFile{Family: view.family, Name: view.name}, map[string]any{"queryDigest": digest}); status != 0 {
		logError(w, status, code)
		return
	}
	f, info, err := openConfined(view.path)
	if err != nil || !os.SameFile(view.info, info) {
		if f != nil {
			f.Close()
		}
		logError(w, 410, errRotated)
		return
	}
	defer f.Close()
	if info.Size() < offset {
		logError(w, 410, errTruncated)
		return
	}
	end, err := completeEnd(f, info.Size())
	if err != nil {
		logError(w, 422, err.Error())
		return
	}
	if offset < 0 || offset > end {
		offset = end
	}
	needle := *req.Text
	match := func(text string) bool { return strings.Contains(text, needle) }
	if *req.CaseInsensitive {
		needle = strings.ToLower(needle)
		match = func(text string) bool { return strings.Contains(strings.ToLower(text), needle) }
	}
	stop := func() bool { return r.Context().Err() != nil }
	var lines []logLine
	var next int64
	var limited bool
	var scanned int64
	if *req.Direction == "forward" {
		lines, next, limited, err = readFilteredForward(f, offset, end, maxSearchMatches, match, searchScanBudget, stop)
		scanned = next - offset
	} else {
		lines, next, limited, err = readFilteredBackward(f, offset, maxSearchMatches, match, searchScanBudget, stop)
		scanned = offset - next
	}
	if err != nil {
		if err == errScanCancelled {
			return // the browser went away; there is nobody to answer
		}
		logError(w, 422, err.Error())
		return
	}
	for i := range lines {
		lines[i].Cursor = logs.cursor(view.token, lines[i].offset)
	}
	complete := (*req.Direction == "forward" && next >= end) || (*req.Direction == "backward" && next == 0)
	operatorJSON(w, 200, map[string]any{"matches": lines, "next": logs.cursor(view.token, next), "limited": limited,
		"complete": complete, "scanned": scanned})
}
