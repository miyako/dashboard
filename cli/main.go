package main

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"time"
	"unicode/utf8"
)

const version = "0.1.4"

func nonce() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

func run(args []string, input io.Reader, output, diagnostic io.Writer) error {
	for _, arg := range args {
		if !utf8.ValidString(arg) {
			return errors.New("arguments must be UTF-8")
		}
	}
	if len(args) == 1 && args[0] == "--version" {
		_, err := fmt.Fprintf(output, "{\"protocol\":1,\"version\":\"%s\"}\n", version)
		return err
	}
	if len(args) == 3 && args[0] == "inspect" && args[1] == "--text" && args[2] != "" && utf8.ValidString(args[2]) {
		// Finite protocol probe also exercises native 4D argument quoting.
		encoder := json.NewEncoder(output)
		encoder.SetEscapeHTML(false)
		return encoder.Encode(map[string]any{"protocol": 1, "text": args[2]})
	}
	if len(args) == 0 || args[0] != "serve" {
		return errors.New("expected serve [--listen IP:port] [--allow-lan --tls-cert file --tls-key file], inspect --text text, or --version")
	}
	flags := flag.NewFlagSet("serve", flag.ContinueOnError)
	flags.SetOutput(diagnostic)
	listen := flags.String("listen", "127.0.0.1:0", "literal local IP and port")
	lan := flags.Bool("allow-lan", false, "explicitly permit non-loopback HTTPS")
	cert := flags.String("tls-cert", "", "TLS certificate")
	key := flags.String("tls-key", "", "TLS key")
	if err := flags.Parse(args[1:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional argument")
	}
	host, port, err := net.SplitHostPort(*listen)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	n, portErr := strconv.Atoi(port)
	if ip == nil || ip.IsUnspecified() || portErr != nil || n < 0 || n > 65535 {
		return errors.New("listen requires a concrete literal IP and valid port; wildcard binds are forbidden")
	}
	if (*cert == "") != (*key == "") {
		return errors.New("TLS certificate and key must be supplied together")
	}
	if !ip.IsLoopback() && (!*lan || *cert == "") {
		return errors.New("LAN access requires --allow-lan and TLS certificate/key")
	}
	var tlsConfig *tls.Config
	if *cert != "" {
		pair, err := tls.LoadX509KeyPair(*cert, *key)
		if err != nil {
			return fmt.Errorf("TLS configuration: %w", err)
		}
		tlsConfig = &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{pair}}
	}
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		return err
	}
	defer listener.Close()
	scheme := "http"
	if *cert != "" {
		scheme = "https"
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	service := newService(scheme+"://"+listener.Addr().String(), nonce())
	server := &http.Server{Handler: service.handler(), TLSConfig: tlsConfig, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	failures := make(chan error, 3)
	go func() {
		encoder := json.NewEncoder(output)
		for {
			select {
			case <-ctx.Done():
				return
			case message := <-service.out:
				if err := encoder.Encode(message); err != nil {
					failures <- fmt.Errorf("stdout: %w", err)
					return
				}
			}
		}
	}()
	go func() {
		if *cert == "" {
			failures <- server.Serve(listener)
		} else {
			failures <- server.ServeTLS(listener, "", "")
		}
	}()
	go func() { failures <- service.read(input) }()
	if err := service.emit(map[string]any{"protocol": 1, "kind": "ready", "url": service.origin + "/#token=" + service.token, "version": version}); err != nil {
		return err
	}
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	defer func() {
		timeout, stop := context.WithTimeout(context.Background(), 2*time.Second)
		defer stop()
		_ = server.Shutdown(timeout)
	}()
	for {
		select {
		case <-ctx.Done():
			return nil
		case err := <-failures:
			return err
		case <-ticker.C:
			service.expire()
			if service.initialized() {
				if _, err := service.request(); err != nil && !errors.Is(err, errBusy) {
					return err
				}
			}
		}
	}
}

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr); err != nil {
		_ = json.NewEncoder(os.Stderr).Encode(map[string]any{"protocol": 1, "error": map[string]string{"code": "dashboard_error", "message": err.Error()}})
		os.Exit(2)
	}
}
