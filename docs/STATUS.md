# Current status

The v2 foundation, configuration gate, runtime/lifecycle hardening gate, deployment-security gate, and runtime-consistency gate are implemented. The control plane now has explicit process ownership, atomic runtime state publication, and a hardened systemd deployment path.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- local HTTP/SOCKS endpoint backend
- optional Privoxy HTTP adapter with runtime-local generated config
- backend lifecycle contract: `validate/start/stop/status/endpoint`
- backend ownership contract: `managed/pid/process_identity`
- backend capability contract
- named profiles and per-profile state
- CLI + TUI profile selection
- ordered route policy and route explanation
- shell environment export with `socks5h`
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
- CI ShellCheck + syntax + systemd contract + functional smoke coverage

## Current engineering gate

The next phase is rootless/operator deployment and backend expansion preparation:

1. add rootless interactive installation without requiring a system account;
2. define installation upgrade/migration checks for existing deployments;
3. separate backend liveness from active network health probes;
4. then evaluate sing-box, mihomo, and HTTP CONNECT backends against the stable contract.
