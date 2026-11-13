package main

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

//go:embed web/*
var assets embed.FS

func sameSecret(a, b string) bool { return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1 }

func (s *service) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		if r.Host != strings.TrimPrefix(strings.TrimPrefix(s.origin, "https://"), "http://") ||
			(r.Header.Get("Origin") != "" && r.Header.Get("Origin") != s.origin) ||
			(strings.HasPrefix(r.URL.Path, "/api/") && r.Header.Get("Sec-Fetch-Site") == "cross-site") {
			http.Error(w, "untrusted host or origin", http.StatusForbidden)
			return
		}
		if r.URL.Path == "/api/session" {
			if r.Method != "POST" || r.Header.Get("Origin") != s.origin {
				http.Error(w, "same-origin POST required", 403)
				return
			}
			body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 128))
			if err != nil || !sameSecret(string(body), s.token) {
				http.Error(w, "invalid token", 401)
				return
			}
			http.SetCookie(w, &http.Cookie{Name: "dashboard", Value: s.cookie, HttpOnly: true, Secure: strings.HasPrefix(s.origin, "https:"), SameSite: http.SameSiteStrictMode, Path: "/"})
			w.WriteHeader(204)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") {
			cookie, err := r.Cookie("dashboard")
			if err != nil || !sameSecret(cookie.Value, s.cookie) {
				http.Error(w, "authentication required", 401)
				return
			}
			switch r.URL.Path {
			case "/api/events":
				s.events(w, r)
			case "/api/refresh":
				if r.Method != "POST" || r.Header.Get("Origin") != s.origin || r.Header.Get("X-Dashboard-Action") != "refresh" {
					http.Error(w, "same-origin refresh POST required", 403)
					return
				}
				id, err := s.request()
				if err != nil {
					http.Error(w, err.Error(), 429)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(202)
				_ = json.NewEncoder(w).Encode(map[string]string{"id": id})
			default:
				http.NotFound(w, r)
			}
			return
		}
		if r.Method != "GET" {
			http.Error(w, "GET required", 405)
			return
		}
		file, contentType := "", ""
		switch r.URL.Path {
		case "/":
			file, contentType = "index.html", "text/html; charset=utf-8"
		case "/app.js":
			file, contentType = "app.js", "text/javascript; charset=utf-8"
		case "/charts.js":
			file, contentType = "charts.js", "text/javascript; charset=utf-8"
		case "/style.css":
			file, contentType = "style.css", "text/css; charset=utf-8"
		default:
			http.NotFound(w, r)
			return
		}
		body, err := assets.ReadFile("web/" + file)
		if err != nil {
			http.Error(w, "asset unavailable", 500)
			return
		}
		w.Header().Set("Content-Type", contentType)
		_, _ = w.Write(body)
	})
}

func (s *service) events(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.Error(w, "GET required", 405)
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unavailable", 500)
		return
	}
	s.mu.Lock()
	if len(s.clients) >= 16 {
		s.mu.Unlock()
		http.Error(w, "viewer limit reached", 503)
		return
	}
	client := make(chan []byte, 1)
	s.clients[client] = true
	body, _ := json.Marshal(s.current)
	client <- body
	s.mu.Unlock()
	defer func() { s.mu.Lock(); delete(s.clients, client); s.mu.Unlock() }()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("X-Accel-Buffering", "no")
	heartbeat := time.NewTicker(5 * time.Second)
	defer heartbeat.Stop()
	for {
		var frame string
		select {
		case <-r.Context().Done():
			return
		case body := <-client:
			frame = "event: state\ndata: " + string(body) + "\n\n"
		case <-heartbeat.C:
			frame = ": keepalive\n\n"
		}
		_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(5 * time.Second))
		if _, err := fmt.Fprint(w, frame); err != nil {
			return
		}
		flusher.Flush()
	}
}
