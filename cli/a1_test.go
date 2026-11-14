package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCacheActionsCatalog(t *testing.T) {
	flush, size := entryFor("cache.flush"), entryFor("cache.size")
	if flush.Tier != "A" || flush.Verify != "none" || flush.Scope != "local" || len(flush.Args) != 0 {
		t.Fatal("cache.flush", flush)
	}
	// The first tier B action: host approval and TLS or loopback are required by the catalog rules.
	if size.Tier != "B" || size.Approval != "operator+host" || size.Transport != "tls_or_loopback_only" || size.Verify != "native" || size.Scope != "local" {
		t.Fatal("cache.size", size)
	}
	canonical := operatorCatalog["cache.size"]
	for _, ok := range []string{`{"sizeMiB":100}`, `{"sizeMiB":1048576}`, `{"sizeMiB":2048}`} {
		if got, err := canonical(json.RawMessage(ok)); err != nil || string(got) != ok {
			t.Fatal(ok, err)
		}
	}
	for _, bad := range []string{`{"sizeMiB":99}`, `{"sizeMiB":1048577}`, `{"sizeMiB":512.5}`, `{"sizeMiB":"512"}`, `{"bytes":1073741824}`, `{"sizeMiB":512,"minFree":1}`, `{}`} {
		if _, err := canonical(json.RawMessage(bad)); err == nil {
			t.Fatal(bad)
		}
	}
	if _, err := operatorCatalog["cache.flush"](json.RawMessage(`{"size":1}`)); err == nil {
		t.Fatal("cache.flush accepted the testing-only size form")
	}
}

func TestCacheSizeNeedsSecureTransportAndIsDefaultDenied(t *testing.T) {
	for origin, want := range map[string]int{"http://127.0.0.1:8123": 201, "http://192.0.2.10:8123": 403} {
		s := newService(origin, viewerToken)
		s.op = newOperator(map[string]bool{"cache.size": true})
		h := frame("hello", 1)
		h.Operator = &operatorCaps{Version: 1, Actions: []string{"cache.size"}}
		if err := s.apply(h); err != nil {
			t.Fatal(err)
		}
		host := strings.TrimPrefix(origin, "http://")
		c := loginAt(t, s, host)
		if w := c.call("POST", "request", `{"action":"cache.size","args":{"sizeMiB":2048}}`, hostIs(host)); w.Code != want {
			t.Fatal(origin, w.Code, w.Body)
		}
	}
	s, c := a0Service(t)
	if w := c.call("POST", "request", `{"action":"cache.size","args":{"sizeMiB":2048}}`); w.Code != 403 || decode(t, w)["error"] != "action_not_enabled" {
		t.Fatal("cache.size not default-denied", w.Code)
	}
	_ = s
}
