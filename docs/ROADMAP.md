# Roadmap

## V2 foundation — completed
- SSH → SOCKS5 backend
- Optional HTTP/Privoxy adapter
- Existing local SOCKS/HTTP endpoint backend
- Domain and IPv4 CIDR policy inspection
- Ordered route rules with exact/suffix/wildcard/CIDR matching
- Environment export
- Health checks and controlled recovery
- Git / Docker / pip / npm integration emitters
- Dependency-light operator TUI
- ShellCheck and functional smoke coverage

## V2 control plane — substantially implemented
- Formal backend capability contract ✅
- Named proxy profiles ✅
- Profile selection from CLI and TUI ✅
- Per-profile state isolation ✅
- Backend endpoint contract ✅
- Ordered route policy and `route` explanation ✅
- Machine-readable `status --json` schema v1 ✅
- Foreground backend mode for systemd ownership ✅
- systemd `Type=simple` + control-group lifecycle ✅

## V2 control plane — next
- Stable status schema expansion: health timestamps, adapter details, process identity
- Configuration validation and versioned schema
- Per-profile systemd template units
- Stronger lifecycle ownership for every managed backend

## V2 backends
1. SSH SOCKS5 ✅
2. Existing local SOCKS/HTTP endpoint ✅
3. sing-box
4. mihomo
5. HTTP CONNECT upstream

Every managed backend implements the same semantic lifecycle contract:
`validate/start/stop/status/endpoint/capabilities`.

## V2 deployment
- Rootless Linux execution
- Container image and host/container network documentation
- Reproducible installation and upgrade path
- Security hardening and least-privilege service account

## V2 observability
- Structured runtime state
- Stable machine-readable status
- Health history and recovery events
- TUI consumes the same state model
