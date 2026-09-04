# Current status

The v2 foundation is now functional as a layered Linux proxy control plane.

Implemented:

- SSH → SOCKS5 backend with AutoSSH
- optional Privoxy HTTP adapter
- domain and IPv4 CIDR route inspection
- shell environment export with `socks5h`
- health check and timed recovery
- Git / Docker / pip / npm integration emitters
- dependency-light operator TUI
- CI ShellCheck + functional smoke coverage

The next engineering gate is runtime hardening and formalization of the backend/profile contract before adding additional heavyweight proxy engines.
