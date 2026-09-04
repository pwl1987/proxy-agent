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
- Profile-safe backend PID ownership ✅
- Port collision refusal for managed local listeners ✅
- Long-lived `proxy-ctl run` service-manager entrypoint ✅
- systemd lifecycle no longer depends on foreground backend environment hacks ✅

## V2 deployment hardening — completed
- Dedicated least-privilege systemd service account ✅
- Configuration ownership/mode enforcement ✅
- Runtime/log directory isolation ✅
- systemd `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, and kernel sandboxing ✅
- Generated Privoxy configuration moved into runtime state ✅
- Rootless interactive installation/execution ✅
- Rootless user systemd services ✅
- Reproducible system/rootless upgrade entrypoints with pre-restore validation ✅
- Non-root container runtime based on `proxy-ctl run` ✅

## V2 backend compatibility — completed
- Separate backend liveness from active network health ✅
- Adapter/backend compatibility matrix and contract tests ✅
- SSH SOCKS5 ✅
- Existing local SOCKS/HTTP endpoint ✅
- sing-box ✅
- mihomo ✅
- HTTP CONNECT upstream ✅

## V2 release engineering — in progress
- Tag-driven release workflow with VERSION/tag consistency gate ✅
- Non-root container build and GHCR publish workflow ✅
- Published image digest capture ✅
- GitHub release generation ✅
- Versioned 0.2.x release/tag ⏳
- Real-binary CI matrix for sing-box/mihomo ⏳
- Structured operational telemetry and health-history inspection ✅
- Host/container networking deployment patterns ✅
- Upgrade rollback verification and compatibility policy ✅
- Container runtime CI execution gate ⏳

## V3 control API — planned
- Typed configuration schema
- Local control API over Unix socket / loopback HTTP
- Desired state vs observed state
- Config revision and optimistic concurrency
- Audit events
- `proxy-ctl exec`
- Capability-versioned backend metadata
- TUI converted from CLI subprocess client to API client

## V4 Web control plane — planned
- Chinese Web UI by default
- Profile/backend/adapter forms driven by capability metadata
- Draft → Validate → Diff → Apply workflow
- Health dashboard and event history
- Rollback to previous configuration revision
- Logs and diagnostics viewer
- Local-only binding by default
- Explicitly enabled remote management with authentication
- Secret references without exposing private keys in the UI

## V5 Cross-platform — planned
- macOS runtime adapter (`launchd`)
- Windows runtime adapter (Windows Service)
- Platform-specific installers
- Linux / macOS / Windows CI matrix
- Shared control API and identical CLI semantics
- Container runtime retained as a universal deployment path

## V6 Production control-plane — target
- Versioned stable API
- Versioned/atomic installation tree
- Metrics endpoint
- Signed/provenance-backed release artifacts
- SBOM and image attestation
- Backup/restore and fleet-ready configuration export
- Compatibility policy for old configuration revisions

## Architecture rule

Do not continue adding large amounts of imperative behavior directly to `proxy-ctl`. Keep the current Shell implementation as the Linux reference implementation while introducing typed configuration and a local control API. Replace the implementation language only after the behavioral contract is frozen.
