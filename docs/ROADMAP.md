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

## V2 control plane — completed
- Formal backend lifecycle contract ✅
- Explicit backend liveness contract ✅
- Formal backend capability contract ✅
- Named proxy profiles ✅
- Profile selection from CLI and TUI ✅
- Per-profile state isolation ✅
- Backend endpoint contract ✅
- Ordered route policy and `route` explanation ✅
- Machine-readable `status --json` schema v1 ✅
- Per-profile systemd services and health timers ✅
- Strict configuration validation and `proxy-ctl validate` ✅

## V2 runtime hardening — completed
- Runtime state schema v2 via `status --json=v2` ✅
- Health markers synchronized into runtime state ✅
- Managed/unmanaged backend ownership contract ✅
- Profile-safe SSH backend PID ownership ✅
- Port collision refusal for managed SSH backend ✅
- Long-lived `proxy-ctl run` service-manager entrypoint ✅
- systemd lifecycle no longer depends on foreground backend environment hacks ✅

## V2 deployment hardening — completed
- Dedicated least-privilege systemd service account ✅
- Root-owned/group-readable configuration with no group/other write access ✅
- Profile permission checks before shell-source evaluation ✅
- Runtime/log directories owned by the service account ✅
- systemd `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, and kernel sandboxing ✅
- Generated Privoxy configuration moved out of `/etc` into runtime state ✅

## V2 runtime consistency — completed
- Profile-local atomic runtime-state lock ✅
- Stale-lock recovery using PID/start-time identity ✅
- Atomic `runtime.json` replacement ✅
- SSH process executable/UID/command-line identity checks ✅
- Exact listener-to-process ownership check ✅
- Stale SSH PID file cleanup ✅

## V2 operator portability — completed
- Rootless interactive installation/execution without requiring a system account ✅
- XDG configuration/profile/runtime paths ✅
- Rootless user systemd service/profile/health templates ✅
- Custom user install paths propagated into generated user units ✅
- Symlink-safe installed entrypoints ✅

## V2 backend compatibility — in progress
- Separate backend liveness from active network health probes ✅
- Define adapter/backend compatibility matrix and tests 🟡
- Current sing-box integration against the stable contract 🟡
- Current mihomo integration against the stable contract
- HTTP CONNECT upstream backend

## V2 backends
1. SSH SOCKS5 ✅
2. Existing local SOCKS/HTTP endpoint ✅
3. sing-box 🟡
4. mihomo
5. HTTP CONNECT upstream

Managed backends implement:
`validate/start/stop/liveness/status/endpoint/managed/pid/process_identity/capabilities`.

## V2 deployment
- Rootless Linux execution ✅
- Container image and host/container network documentation
- Reproducible installation and upgrade path ✅
- Security hardening and least-privilege service account ✅
- Configuration ownership/mode verification ✅

## V2 observability
- Structured runtime state ✅
- Stable machine-readable status ✅
- Health history and recovery events ✅
- TUI consumes the same state model