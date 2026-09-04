# Current status

The v2 foundation, configuration gate, runtime/lifecycle hardening gate, deployment-security gate, runtime-consistency gate, rootless operator gate, and health-semantics gate are implemented. The control plane now supports both host-wide least-privilege systemd deployment and a rootless user-scoped operator deployment.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- local HTTP/SOCKS endpoint backend
- optional Privoxy HTTP adapter with runtime-local generated config
- backend lifecycle contract: `validate/start/stop/liveness/status/endpoint`
- backend ownership contract: `managed/pid/process_identity`
- backend capability contract
- named profiles and per-profile state
- CLI + TUI profile selection
- ordered route policy and route explanation
- shell environment export with `socks5h`
- backend liveness separated from active network-health probes
- configurable network-health requirement via `HEALTH_NETWORK_REQUIRED`
- health check, timed recovery, and runtime state synchronization
- Git / Docker / pip / npm integration emitters
- systemd service-manager ownership through `proxy-ctl run`
- profile-safe SSH process ownership and port-collision refusal
- SSH UID/executable/command-line/listener ownership verification
- strict configuration validation through `proxy-ctl validate`
- runtime state schema v2 through `proxy-ctl status --json=v2`
- profile-local atomic runtime-state lock with stale-lock recovery
- configuration ownership/mode validation before shell-source evaluation
- dedicated `proxy-agent` service account with systemd sandboxing
- runtime/log directory isolation
- generated Privoxy configuration moved out of `/etc`
- rootless `install-user.sh` with XDG configuration/profile/runtime paths
- rootless user systemd service/profile/health templates
- symlink-safe executable path resolution for installed CLI/TUI/health entrypoints
- CI ShellCheck + syntax + systemd contract + functional smoke coverage

## Current engineering gate

The next phase is backend compatibility and expansion:

1. freeze the `liveness/status/network-health/recovery` semantic matrix for every backend;
2. add backend/adapter compatibility contract tests;
3. evaluate current sing-box support against the stable lifecycle/capability contract;
4. evaluate mihomo and HTTP CONNECT backends only after the compatibility boundary is explicit.
