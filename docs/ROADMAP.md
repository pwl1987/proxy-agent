# Roadmap

## V2 foundation — completed

- SSH → SOCKS5 backend
- Optional HTTP/Privoxy adapter
- Domain and IPv4 CIDR policy inspection
- Environment export
- Health checks and controlled recovery
- Git / Docker / pip / npm integration emitters
- Dependency-light operator TUI
- ShellCheck and functional smoke coverage

## V2 control plane — in progress

- Formal backend capability contract ✅
- Named proxy profiles ✅
- Profile selection from CLI and TUI ✅
- Per-profile listeners and state ✅
- Backend endpoint contract ✅
- Route priorities, wildcard domains and explicit proxy/direct rules
- `route explain` with ordered policy evaluation
- Structured state and machine-readable status
- Better lifecycle ownership under systemd

## V2 backends

Prioritize backends by operational value rather than adding wrappers indiscriminately:

1. SSH SOCKS5 ✅
2. Existing local SOCKS/HTTP endpoint
3. sing-box
4. mihomo
5. HTTP CONNECT upstream

Every backend implements the same semantic lifecycle contract:

```text
validate()
start()
stop()
status()
endpoint()
capabilities()
```

Backend-specific behavior stays inside `backends/<name>.sh`; the control plane consumes only the contract.

## V2 runtime

- Rootless operation where possible
- Container image and documented container networking modes
- systemd hardening
- health metrics and event history
- upgrade / rollback workflow
- configuration validation before activation

## TUI evolution

The dependency-light TUI is already usable for daily operator work. Next additions:

- backend and adapter cards
- live health/event stream
- route explorer with policy order
- configuration validation screen
- restart confirmation for destructive actions
- log viewer

The TUI remains a client of the same control-plane semantics and never becomes a second backend implementation.
