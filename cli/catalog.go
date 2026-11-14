package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"time"
)

// actions.json is the single action catalog; the 4D component ships a byte-identical copy
// (component/dashboard/Resources/actions.json), checked by tests/test_actions_catalog.py.
//
//go:embed actions.json
var catalogJSON []byte

type argSpec struct {
	Type    string  `json:"type"`
	Pattern string  `json:"pattern,omitempty"`
	Min     *int64  `json:"min,omitempty"`
	Max     *int64  `json:"max,omitempty"`
	Enum    []int64 `json:"enum,omitempty"`
	re      *regexp.Regexp
}

type catalogEntry struct {
	ID         string              `json:"id"`
	Tier       string              `json:"tier"`
	Scope      string              `json:"scope"`
	DeadlineMs int64               `json:"deadlineMs"`
	Exclusive  bool                `json:"exclusive"`
	Progress   bool                `json:"progress"`
	Verify     string              `json:"verify"`
	Approval   string              `json:"approval"`
	Transport  string              `json:"transport"`
	Args       map[string]*argSpec `json:"args"`
}

var catalogEntries = map[string]*catalogEntry{}
var integerLiteral = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)

func init() {
	entries, err := parseCatalog(catalogJSON)
	if err != nil {
		panic(err)
	}
	for _, e := range entries {
		entry := e
		catalogEntries[entry.ID] = entry
		operatorCatalog[entry.ID] = func(raw json.RawMessage) (json.RawMessage, error) { return entry.canonical(raw) }
	}
}

func parseCatalog(raw []byte) ([]*catalogEntry, error) {
	var catalog struct {
		Version int             `json:"version"`
		Actions []*catalogEntry `json:"actions"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&catalog); err != nil || catalog.Version != 1 || len(catalog.Actions) == 0 {
		return nil, fmt.Errorf("invalid action catalog: %v", err)
	}
	seen := map[string]bool{}
	for _, e := range catalog.Actions {
		if !identifier.MatchString(e.ID) || seen[e.ID] || e.DeadlineMs < 1000 || e.DeadlineMs > 3600000 ||
			(e.Tier != "A" && e.Tier != "B" && e.Tier != "C") || (e.Scope != "any" && e.Scope != "local" && e.Scope != "standalone" && e.Scope != "server") ||
			(e.Verify != "none" && e.Verify != "cli" && e.Verify != "native") ||
			(e.Approval != "operator" && e.Approval != "operator+host") || (e.Transport != "any" && e.Transport != "tls_or_loopback_only") ||
			(e.Tier != "A" && (e.Approval != "operator+host" || e.Transport != "tls_or_loopback_only")) {
			return nil, fmt.Errorf("invalid action catalog entry %q", e.ID)
		}
		seen[e.ID] = true
		for name, spec := range e.Args {
			if !identifier.MatchString(name) || spec == nil {
				return nil, fmt.Errorf("invalid argument %q in %q", name, e.ID)
			}
			switch spec.Type {
			case "text":
				re, err := regexp.Compile(spec.Pattern)
				if err != nil || spec.Pattern == "" || spec.Pattern[0] != '^' || spec.Pattern[len(spec.Pattern)-1] != '$' {
					return nil, fmt.Errorf("argument %q in %q needs an anchored pattern", name, e.ID)
				}
				spec.re = re
			case "integer":
				if len(spec.Enum) == 0 && (spec.Min == nil || spec.Max == nil || *spec.Min > *spec.Max) {
					return nil, fmt.Errorf("argument %q in %q needs an enum or min and max", name, e.ID)
				}
			default:
				return nil, fmt.Errorf("argument %q in %q has an unknown type", name, e.ID)
			}
		}
	}
	return catalog.Actions, nil
}

// canonical validates arguments against the entry and returns them as sorted-key JSON.
func (e *catalogEntry) canonical(raw json.RawMessage) (json.RawMessage, error) {
	var fields map[string]json.RawMessage
	if err := strictDecode(raw, &fields); err != nil || fields == nil || len(fields) != len(e.Args) {
		return nil, errors.New("arguments do not match the catalog")
	}
	out := map[string]any{}
	for name, spec := range e.Args {
		value, ok := fields[name]
		if !ok {
			return nil, errors.New("missing argument " + name)
		}
		switch spec.Type {
		case "text":
			var text string
			if json.Unmarshal(value, &text) != nil || !spec.re.MatchString(text) {
				return nil, errors.New("invalid argument " + name)
			}
			out[name] = text
		case "integer":
			literal := string(bytes.TrimSpace(value))
			n, err := strconv.ParseInt(literal, 10, 64)
			if !integerLiteral.MatchString(literal) || err != nil || !spec.allows(n) {
				return nil, errors.New("invalid argument " + name)
			}
			out[name] = n
		}
	}
	return json.Marshal(out)
}

func (s *argSpec) allows(n int64) bool {
	if len(s.Enum) > 0 {
		for _, v := range s.Enum {
			if v == n {
				return true
			}
		}
		return false
	}
	return n >= *s.Min && n <= *s.Max
}

// entryFor returns the catalog entry, or a conservative default for test-only validators.
func entryFor(id string) *catalogEntry {
	if e, ok := catalogEntries[id]; ok {
		return e
	}
	return &catalogEntry{ID: id, Tier: "A", Scope: "any", DeadlineMs: 30000, Verify: "none", Approval: "operator", Transport: "any"}
}

func (e *catalogEntry) deadline() time.Duration {
	return time.Duration(e.DeadlineMs) * time.Millisecond
}

func catalogIDs() []string {
	ids := make([]string, 0, len(catalogEntries))
	for id := range catalogEntries {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}
