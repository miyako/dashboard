package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// logAccessTimeout bounds the wait for 4D's authorization and audit of an open (a variable for tests).
var logAccessTimeout = 5 * time.Second

// Log browsing (L1): see docs/log-browsing-design.md. The CLI reads a closed catalog of families
// from the host Logs folder 4D gives it; 4D authorizes and audits every open (fail-closed).

//go:embed logs.json
var logsCatalogJSON []byte

const (
	maxLogFiles       = 256
	maxPageBytes      = 256 << 10
	maxPageLines      = 500
	maxLineBytes      = 16 << 10
	maxLineScan       = 16 << 20
	logPageRate       = 240
	maxExpiredAccess  = 32
	defaultTailLines  = 100
	logsProtocol      = 1
	errRotated        = "rotated"
	errTruncated      = "truncated"
	errInvalidCursor  = "invalid_cursor"
	errUnknownLogFile = "unknown_log_file"
)

type logFamily struct {
	ID          string `json:"id"`
	Dir         string `json:"dir"`
	Pattern     string `json:"pattern"`
	Format      string `json:"format"`
	Sensitivity string `json:"sensitivity"`
	re          *regexp.Regexp
}

var logFamilies = map[string]*logFamily{}
var logDir = regexp.MustCompile(`^[A-Za-z0-9_-]{0,32}$`)

func init() {
	families, err := parseLogCatalog(logsCatalogJSON)
	if err != nil {
		panic(err)
	}
	for _, f := range families {
		logFamilies[f.ID] = f
	}
}

func parseLogCatalog(raw []byte) ([]*logFamily, error) {
	var catalog struct {
		Version  int          `json:"version"`
		Families []*logFamily `json:"families"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&catalog); err != nil || catalog.Version != 1 || len(catalog.Families) == 0 {
		return nil, fmt.Errorf("invalid log catalog: %v", err)
	}
	seen := map[string]bool{}
	for _, f := range catalog.Families {
		if !identifier.MatchString(f.ID) || seen[f.ID] || !logDir.MatchString(f.Dir) ||
			(f.Format != "jsonl" && f.Format != "text" && f.Format != "tsv") ||
			(f.Sensitivity != "normal" && f.Sensitivity != "sensitive") ||
			!strings.HasPrefix(f.Pattern, "^") || !strings.HasSuffix(f.Pattern, "$") {
			return nil, fmt.Errorf("invalid log family %q", f.ID)
		}
		re, err := regexp.Compile(f.Pattern)
		if err != nil {
			return nil, fmt.Errorf("invalid log family pattern %q", f.ID)
		}
		f.re, seen[f.ID] = re, true
	}
	return catalog.Families, nil
}

type logsCaps struct {
	Version  int      `json:"version"`
	Families []string `json:"families"`
}

type logView struct {
	token, actor, family, name, path string
	info                             os.FileInfo
}

type logDecision struct {
	ok   bool
	code string
}

type logsConfig struct {
	root       string
	families   map[string]*logFamily
	key        []byte
	negotiated bool
	views      map[string]*logView // by actor: one open view per operator session
	pending    map[string]chan logDecision
	waiting    map[string]bool // actors with an open waiting for 4D
	expired    []string
	pages      []time.Time
}

func parseLogFamilies(list string) (map[string]*logFamily, error) {
	families := map[string]*logFamily{}
	for _, id := range strings.Split(list, ",") {
		f, ok := logFamilies[id]
		if !ok || families[id] != nil {
			return nil, errors.New("log families must be unique catalog IDs")
		}
		families[id] = f
	}
	return families, nil
}

// newLogs requires an absolute, existing, non-symlinked root directory.
func newLogs(root string, families map[string]*logFamily) (*logsConfig, error) {
	if !filepath.IsAbs(root) {
		return nil, errors.New("logs root must be an absolute path")
	}
	info, err := os.Lstat(root)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return nil, errors.New("logs root must be an existing directory, not a symlink")
	}
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return nil, err
	}
	return &logsConfig{root: filepath.Clean(root), families: families, key: key, views: map[string]*logView{},
		pending: map[string]chan logDecision{}, waiting: map[string]bool{}}, nil
}

func (l *logsConfig) caps() logsCaps {
	caps := logsCaps{Version: logsProtocol}
	for id := range l.families {
		caps.Families = append(caps.Families, id)
	}
	sort.Strings(caps.Families)
	return caps
}

func (s *service) negotiateLogsLocked(caps *logsCaps) error {
	if s.logs == nil {
		if caps != nil {
			return errors.New("hello declares log families the CLI did not enable")
		}
		return nil
	}
	want := s.logs.caps()
	if caps == nil || caps.Version != logsProtocol || len(caps.Families) != len(want.Families) {
		return errors.New("hello log declaration does not match the CLI")
	}
	seen := map[string]bool{}
	for _, id := range caps.Families {
		if s.logs.families[id] == nil || seen[id] {
			return errors.New("hello log declaration does not match the CLI")
		}
		seen[id] = true
	}
	s.logs.negotiated = true
	return nil
}

func (l *logsConfig) mac(parts ...string) string {
	h := hmac.New(sha256.New, l.key)
	for _, p := range parts {
		h.Write([]byte(p))
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))[:32]
}

func (l *logsConfig) fileID(family, name string) string { return l.mac("file", family, name) }

type logFile struct {
	ID       string `json:"id"`
	Family   string `json:"family"`
	Name     string `json:"name"`
	Size     int64  `json:"size"`
	Modified string `json:"modified"`
	path     string
}

// list returns regular, non-symlinked files whose base name matches an enabled family (newest first).
func (l *logsConfig) list() []logFile {
	files := []logFile{}
	for _, f := range l.families {
		dir := filepath.Join(l.root, f.Dir)
		if info, err := os.Lstat(dir); err != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			continue
		}
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			name := e.Name()
			if !f.re.MatchString(name) || strings.ContainsAny(name, "/\\\x00") {
				continue
			}
			path := filepath.Join(dir, name)
			info, err := os.Lstat(path)
			if err != nil || !info.Mode().IsRegular() {
				continue
			}
			files = append(files, logFile{ID: l.fileID(f.ID, name), Family: f.ID, Name: name, Size: info.Size(),
				Modified: stamp(info.ModTime()), path: path})
		}
	}
	sort.Slice(files, func(i, j int) bool {
		if files[i].Modified != files[j].Modified {
			return files[i].Modified > files[j].Modified
		}
		return files[i].Name < files[j].Name
	})
	if len(files) > maxLogFiles {
		files = files[:maxLogFiles]
	}
	return files
}

func (l *logsConfig) resolve(id string) (logFile, bool) {
	for _, f := range l.list() {
		if hmac.Equal([]byte(f.ID), []byte(id)) {
			return f, true
		}
	}
	return logFile{}, false
}

// openConfined opens a regular file read-only and proves the handle is the file that was checked.
func openConfined(path string) (*os.File, os.FileInfo, error) {
	checked, err := os.Lstat(path)
	if err != nil || checked.Mode()&os.ModeSymlink != 0 || !checked.Mode().IsRegular() {
		return nil, nil, errors.New("not a regular file")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	opened, err := f.Stat()
	if err != nil || !os.SameFile(checked, opened) || !opened.Mode().IsRegular() {
		f.Close()
		return nil, nil, errors.New("file changed while opening")
	}
	return f, opened, nil
}

func (l *logsConfig) cursor(view string, offset int64) string {
	text := strconv.FormatInt(offset, 10)
	return text + "." + l.mac("cursor", view, text)
}

func (l *logsConfig) parseCursor(view, cursor string) (int64, bool) {
	text, sig, ok := strings.Cut(cursor, ".")
	if !ok || !hmac.Equal([]byte(sig), []byte(l.mac("cursor", view, text))) {
		return 0, false
	}
	offset, err := strconv.ParseInt(text, 10, 64)
	return offset, err == nil && offset >= 0
}

type logLine struct {
	Text      string `json:"text"`
	Truncated bool   `json:"truncated,omitempty"`
	Cursor    string `json:"cursor"`
	offset    int64
}

func lineText(raw []byte) (string, bool) {
	raw = bytes.TrimSuffix(raw, []byte("\r"))
	truncated := len(raw) > maxLineBytes
	if truncated {
		raw = raw[:maxLineBytes]
		// A rune cut at the boundary becomes U+FFFD below, like any other invalid byte.
	}
	return strings.ToValidUTF8(string(raw), "�"), truncated
}

// completeEnd is the end of the last complete (newline-terminated) line; a partial last line is held back.
func completeEnd(f *os.File, size int64) (int64, error) {
	pos := size
	block := make([]byte, 64<<10)
	for pos > 0 && size-pos < maxLineScan {
		start := pos - int64(len(block))
		if start < 0 {
			start = 0
		}
		n, err := f.ReadAt(block[:pos-start], start)
		if err != nil && err != io.EOF {
			return 0, err
		}
		if i := bytes.LastIndexByte(block[:n], '\n'); i >= 0 {
			return start + int64(i) + 1, nil
		}
		pos = start
	}
	if pos == 0 {
		return 0, nil
	}
	return 0, errors.New("line_too_long")
}

// readForward returns up to limit complete lines starting at a line start.
func readForward(f *os.File, from, end int64, limit int) ([]logLine, int64, error) {
	lines := []logLine{}
	pos := from
	buf := make([]byte, maxPageBytes)
	read := int64(0)
	for pos < end && len(lines) < limit && read < maxPageBytes {
		n, err := f.ReadAt(buf[:min(int64(len(buf)), end-pos)], pos)
		if err != nil && err != io.EOF {
			return nil, 0, err
		}
		chunk := buf[:n]
		i := bytes.IndexByte(chunk, '\n')
		if i < 0 {
			// A line longer than a page: show its head, then skip to its newline.
			text, _ := lineText(chunk)
			next, err := skipToNewline(f, pos+int64(n), end)
			if err != nil {
				return nil, 0, err
			}
			lines = append(lines, logLine{Text: text, Truncated: true, offset: pos})
			read += next - pos
			pos = next
			continue
		}
		for i >= 0 && len(lines) < limit {
			text, truncated := lineText(chunk[:i])
			lines = append(lines, logLine{Text: text, Truncated: truncated, offset: pos})
			pos += int64(i) + 1
			read += int64(i) + 1
			chunk = chunk[i+1:]
			i = bytes.IndexByte(chunk, '\n')
		}
	}
	return lines, pos, nil
}

func skipToNewline(f *os.File, from, end int64) (int64, error) {
	block := make([]byte, 64<<10)
	for pos := from; pos < end && pos-from < maxLineScan; {
		n, err := f.ReadAt(block[:min(int64(len(block)), end-pos)], pos)
		if err != nil && err != io.EOF {
			return 0, err
		}
		if i := bytes.IndexByte(block[:n], '\n'); i >= 0 {
			return pos + int64(i) + 1, nil
		}
		pos += int64(n)
	}
	return 0, errors.New("line_too_long")
}

// readBackward returns up to limit complete lines that end before a line start, oldest first.
func readBackward(f *os.File, before int64, limit int) ([]logLine, error) {
	starts := []int64{}
	pos := before
	// Walk back line by line from `before`: each line start is just after the previous newline.
	for len(starts) < limit && pos > 0 {
		start, err := previousLineStart(f, pos)
		if err != nil {
			return nil, err
		}
		starts = append(starts, start)
		pos = start
	}
	lines := []logLine{}
	for i := len(starts) - 1; i >= 0; i-- {
		end := before
		if i > 0 {
			end = starts[i-1]
		}
		got, _, err := readForward(f, starts[i], end, 1)
		if err != nil {
			return nil, err
		}
		lines = append(lines, got...)
	}
	return lines, nil
}

func previousLineStart(f *os.File, lineEnd int64) (int64, error) {
	// lineEnd is a line start, so lineEnd-1 is the newline ending the previous line.
	pos := lineEnd - 1
	block := make([]byte, 64<<10)
	for pos > 0 && lineEnd-pos < maxLineScan {
		start := pos - int64(len(block))
		if start < 0 {
			start = 0
		}
		n, err := f.ReadAt(block[:pos-start], start)
		if err != nil && err != io.EOF {
			return 0, err
		}
		if i := bytes.LastIndexByte(block[:n], '\n'); i >= 0 {
			return start + int64(i) + 1, nil
		}
		pos = start
	}
	if pos <= 0 {
		return 0, nil
	}
	return 0, errors.New("line_too_long")
}

func logError(w http.ResponseWriter, status int, code string) { operatorError(w, status, code) }

// logsRoute serves /api/operator/logs/*; the operator request checks already ran.
func (s *service) logsRoute(w http.ResponseWriter, r *http.Request, route string, body []byte) {
	s.mu.Lock()
	if s.logs == nil {
		s.mu.Unlock()
		http.NotFound(w, r)
		return
	}
	session := s.operatorSessionLocked(r)
	if session == nil {
		s.mu.Unlock()
		operatorError(w, 401, "operator_authentication_required")
		return
	}
	if !s.secureOrLoopback() {
		s.mu.Unlock()
		logError(w, 403, "transport_not_allowed")
		return
	}
	logs, actor := s.logs, session.actor
	s.mu.Unlock()
	switch route {
	case "files":
		if r.Method != "GET" {
			logError(w, 405, "get_required")
			return
		}
		operatorJSON(w, 200, map[string]any{"files": logs.list()})
	case "open":
		s.logsOpen(w, body, logs, actor)
	case "page":
		if r.Method != "GET" {
			logError(w, 405, "get_required")
			return
		}
		s.logsPage(w, r, logs, actor)
	default:
		logError(w, 404, "unknown_route")
	}
}

func (s *service) logsOpen(w http.ResponseWriter, body []byte, logs *logsConfig, actor string) {
	var req struct {
		File *string `json:"file"`
	}
	if strictDecode(body, &req) != nil || req.File == nil {
		logError(w, 400, "invalid_body")
		return
	}
	file, ok := logs.resolve(*req.File)
	if !ok {
		logError(w, 404, errUnknownLogFile)
		return
	}
	s.mu.Lock()
	if !logs.negotiated || s.current.Epoch == "" || s.current.Status != "connected" {
		s.mu.Unlock()
		logError(w, 409, "target_unavailable")
		return
	}
	if logs.waiting[actor] {
		s.mu.Unlock()
		logError(w, 429, "open_pending")
		return
	}
	id := nonce()
	decision := make(chan logDecision, 1)
	if err := s.emit(map[string]any{"protocol": 1, "kind": "logAccess", "epoch": s.current.Epoch, "id": id,
		"op": "open", "family": file.Family, "file": file.Name, "actor": actor}); err != nil {
		s.mu.Unlock()
		logError(w, 503, "dispatch_failed")
		return
	}
	logs.pending[id], logs.waiting[actor] = decision, true
	s.mu.Unlock()
	// Wait for 4D's authorization and audit outside the service lock: nothing else is blocked.
	var result logDecision
	select {
	case result = <-decision:
	case <-time.After(logAccessTimeout):
		result = logDecision{code: "authorization_timeout"}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, still := logs.pending[id]; still {
		delete(logs.pending, id)
		logs.expired = append(logs.expired, id)
		if len(logs.expired) > maxExpiredAccess {
			logs.expired = logs.expired[len(logs.expired)-maxExpiredAccess:]
		}
	}
	delete(logs.waiting, actor)
	if !result.ok {
		status := 403
		if result.code == "authorization_timeout" {
			status = 504
		}
		logError(w, status, result.code)
		return
	}
	f, info, err := openConfined(file.path)
	if err != nil {
		logError(w, 410, errRotated)
		return
	}
	defer f.Close()
	view := &logView{token: nonce(), actor: actor, family: file.Family, name: file.Name, path: file.path, info: info}
	logs.views[actor] = view
	end, err := completeEnd(f, info.Size())
	if err != nil {
		logError(w, 422, err.Error())
		return
	}
	lines, err := readBackward(f, end, defaultTailLines)
	if err != nil {
		logError(w, 422, err.Error())
		return
	}
	operatorJSON(w, 200, map[string]any{"view": view.token, "file": map[string]any{"id": file.ID, "family": file.Family,
		"name": file.Name, "size": info.Size()}, "page": logs.pageBody(view, lines, end, end)})
}

func (l *logsConfig) pageBody(view *logView, lines []logLine, after int64, end int64) map[string]any {
	for i := range lines {
		lines[i].Cursor = l.cursor(view.token, lines[i].offset)
	}
	first := after
	if len(lines) > 0 {
		first = lines[0].offset
	}
	return map[string]any{"lines": lines, "before": l.cursor(view.token, first), "after": l.cursor(view.token, after),
		"atStart": first == 0, "atEnd": after >= end}
}

func (s *service) logsPage(w http.ResponseWriter, r *http.Request, logs *logsConfig, actor string) {
	query := r.URL.Query()
	s.mu.Lock()
	view := logs.views[actor]
	now := time.Now()
	window := logs.pages[:0]
	for _, at := range logs.pages {
		if now.Sub(at) < time.Minute {
			window = append(window, at)
		}
	}
	logs.pages = window
	limited := len(logs.pages) >= logPageRate
	if !limited {
		logs.pages = append(logs.pages, now)
	}
	s.mu.Unlock()
	if limited {
		logError(w, 429, "rate_limited")
		return
	}
	if view == nil || !hmac.Equal([]byte(view.token), []byte(query.Get("view"))) {
		logError(w, 404, "unknown_view")
		return
	}
	offset, ok := logs.parseCursor(view.token, query.Get("cursor"))
	direction := query.Get("direction")
	limit, err := strconv.Atoi(query.Get("limit"))
	if !ok || (direction != "forward" && direction != "backward") || err != nil || limit < 1 || limit > maxPageLines || len(query) != 4 {
		logError(w, 400, errInvalidCursor)
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
	if offset > end {
		offset = end
	}
	var lines []logLine
	after := offset
	if direction == "forward" {
		lines, after, err = readForward(f, offset, end, limit)
	} else {
		lines, err = readBackward(f, offset, limit)
	}
	if err != nil {
		logError(w, 422, err.Error())
		return
	}
	operatorJSON(w, 200, logs.pageBody(view, lines, after, end))
}

// applyLogAccessResultLocked delivers 4D's decision to the waiting open, or drops a late one.
func (s *service) applyLogAccessResultLocked(m message) error {
	if s.logs == nil || !s.logs.negotiated || !hex64.MatchString(m.ID) || m.OK == nil ||
		(*m.OK && m.Error != "") || (!*m.OK && !errorCode.MatchString(m.Error)) {
		return errors.New("invalid logAccessResult")
	}
	if ch, ok := s.logs.pending[m.ID]; ok {
		delete(s.logs.pending, m.ID)
		ch <- logDecision{ok: *m.OK, code: m.Error}
		return nil
	}
	for i, id := range s.logs.expired {
		if id == m.ID {
			s.logs.expired = append(s.logs.expired[:i], s.logs.expired[i+1:]...)
			return nil
		}
	}
	return errors.New("uncorrelated logAccessResult")
}
