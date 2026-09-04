# Roadmap

## V2 foundation — current

- SSH → SOCKS5 backend
- Optional HTTP/Privoxy adapter
- Domain and IPv4 CIDR policy inspection
- Environment export
- Health checks and controlled recovery
- Git / Docker / pip / npm integration emitters
- Dependency-light operator TUI
- ShellCheck and functional smoke coverage

## V2 control plane

- Formal backend capability contract
- Named proxy profiles
- Profile selection from CLI and TUI
- Per-profile listeners and state
- Route priorities, wildcard domains and explicit proxy/direct rules
- `route explain` with ordered policy evaluation
- Structured state and machine-readable status
- Better lifecycle ownership under systemd

## V2 backends

Prioritize backends by operational value rather than adding wrappers indiscriminately:

1. SSH SOCKS5
2. Existing local SOCKS/HTTP endpoint
3. sing-box
4. mihomo
5. HTTP CONNECT upstream

Every backend should implement the same semantic lifecycle contract and expose a local endpoint to adapters/integrations.

## V2 runtime

- Rootless operation where possible
- Container image and documented container networking modes
- systemd hardening
- health metrics and event history
- upgrade / rollback workflow
- configuration validation before activation

## TUI evolution

The first TUI is deliberately thin. Later versions can add:

- profile selector
- backend and adapter cards
- live health/event stream
- route explorer
- configuration validation screen
- restart confirmation for destructive actions
- log viewer

The TUI must remain a client of the same control-plane API/CLI semantics; it must never become a second implementation of backend logic.
