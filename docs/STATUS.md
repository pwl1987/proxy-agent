# Current status

The v2 foundation, configuration gate, and runtime/lifecycle hardening gate are implemented. The control plane now has explicit backend ownership semantics and a manager-safe runtime state model.

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
- systemd foreground-free service ownership through `proxy-ctl run`
- profile-safe SSH process ownership and port-collision refusal
- strict configuration validation through `proxy-ctl validate`
- runtime state schema v2 through `proxy-ctl status --json=v2`
- CI ShellCheck + syntax + systemd contract + functional smoke coverage

## Current engineering gate

The next phase is deployment hardening before adding heavyweight proxy engines:

1. verify privileged configuration ownership and file modes;
2. introduce least-privilege/rootless execution paths;
3. strengthen process identity and listener verification;
4. add atomic runtime-state locking and stale-state cleanup;
5. then evaluate sing-box, mihomo, and HTTP CONNECT backends against the stable contract.
