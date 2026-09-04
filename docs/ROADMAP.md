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

## V2 release engineering — next
- Versioned 0.2.x release/tag
- Reproducible container image build/publish and digest capture
- Real-binary optional CI matrix for sing-box/mihomo
- Structured operational telemetry and health-history inspection
- Host/container networking deployment patterns
- Upgrade rollback strategy and compatibility policy
