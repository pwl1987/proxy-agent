# Current status

`proxy-agent` 0.2.0 is the current engineering baseline. The project now has a complete backend compatibility layer covering managed local proxy engines and unmanaged upstream endpoints, plus system, rootless, and container deployment modes.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- local HTTP/SOCKS endpoint backend
- sing-box managed backend
- mihomo managed backend
- HTTP CONNECT unmanaged upstream backend
- optional Privoxy HTTP adapter
- backend lifecycle contract: `validate/start/stop/liveness/status/endpoint`
- backend ownership contract: `managed/pid/process_identity`
- backend capability contract
- named profiles and per-profile state
- CLI + TUI profile selection
- ordered route policy and route explanation
- shell environment export with `socks5h`
- backend liveness separated from active network-health probes
- configurable network-health requirement via `HEALTH_NETWORK_REQUIRED`
- health checks, recovery, and runtime state synchronization
- Git / Docker / pip / npm integration emitters
- systemd service-manager ownership through `proxy-ctl run`
- profile-safe process ownership and listener checks
- strict configuration validation through `proxy-ctl validate`
- runtime state schema v2 through `proxy-ctl status --json=v2`
- profile-local atomic runtime-state lock with stale-lock recovery
- configuration ownership/mode validation before shell-source evaluation
- dedicated least-privilege systemd service account and sandboxing
- rootless `install-user.sh` with XDG configuration/profile/runtime paths
- rootless user systemd service/profile/health templates
- reproducible `upgrade.sh` and `upgrade-user.sh` with configuration preservation and pre-restore validation
- non-root `Containerfile` runtime with `proxy-ctl run` as the single foreground process
- container healthcheck and host/container deployment documentation
- CI ShellCheck + syntax + backend contract + systemd + functional + TUI + CLI + rootless + container gates

## Engineering gate

The backend compatibility gate is complete. The next work should focus on production packaging and observability rather than adding more backend-specific semantics:

1. publish a versioned release/tag from the 0.2.0 baseline;
2. add reproducible container image build/publish automation with digest capture;
3. strengthen structured runtime telemetry and health-history inspection;
4. add integration tests against real sing-box/mihomo binaries in an optional CI matrix;
5. document host/container networking patterns for common deployment environments.
