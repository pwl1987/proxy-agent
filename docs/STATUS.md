# Current status

The v2 foundation, configuration gate, runtime/lifecycle hardening gate, and first deployment-security gate are implemented. The control plane now has explicit backend ownership semantics, a manager-safe runtime state model, and a dedicated least-privilege systemd deployment path.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- local HTTP/SOCKS endpoint backend
- optional Privoxy HTTP adapter
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
- strict configuration validation through `proxy-ctl validate`
- runtime state schema v2 through `proxy-ctl status --json=v2`
- configuration ownership/mode validation before shell-source evaluation
- dedicated `proxy-agent` service account with systemd sandboxing
- runtime/log directory isolation and runtime-local Privoxy configuration
- CI ShellCheck + syntax + systemd contract + functional smoke coverage

## Current engineering gate

The next phase is compatibility and expansion, not basic infrastructure repair:

1. add rootless interactive installation without relying on a system account;
2. add atomic runtime-state locking and stale-state cleanup;
3. strengthen managed-process identity with executable, UID, and exact listener binding checks;
4. separate backend liveness from active network health probes;
5. only then add heavyweight engines such as sing-box, mihomo, and HTTP CONNECT against the stable backend contract.
