# Current status

The v2 foundation and first control-plane hardening gate are complete. The project now has a backend-neutral lifecycle contract, named profiles, profile-aware systemd services, strict configuration validation, routing policy inspection, health recovery, and a common machine-facing status surface.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- local HTTP/SOCKS endpoint backend
- optional Privoxy HTTP adapter
- backend lifecycle contract: `validate/start/stop/status/endpoint`
- backend capability contract
- named profiles and per-profile state
- CLI + TUI profile selection
- ordered route policy and route explanation
- shell environment export with `socks5h`
- health check and timed recovery
- Git / Docker / pip / npm integration emitters
- systemd foreground ownership with per-profile units
- strict configuration validation through `proxy-ctl validate`
- CI ShellCheck + syntax + systemd contract + functional smoke coverage

## Current engineering gate

The next phase is runtime-state formalization and lifecycle ownership hardening:

1. expand the machine-readable status schema without breaking schema v1 consumers;
2. record health timestamps, adapter state, and managed process identity;
3. make interactive backend stop operations profile-safe without broad process matching;
4. then move into rootless/least-privilege deployment and additional proxy engines.
