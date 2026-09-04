# Backend Contract

Backends live under `backends/<name>.sh` and are loaded dynamically by `proxy-ctl`.

A backend named `foo-bar` must implement the following shell functions:

```bash
backend_foo_bar_validate
backend_foo_bar_start
backend_foo_bar_stop
backend_foo_bar_status
backend_foo_bar_endpoint
backend_foo_bar_managed
backend_foo_bar_pid
backend_foo_bar_process_identity
```

It may also expose capability metadata colocated with the backend:

```bash
backend_foo_bar_capability
backend_foo_bar_capabilities
```

`lib/backend.sh` owns discovery and lifecycle dispatch. `lib/backend-capabilities.sh` is only the generic consumer for capability metadata; capability definitions do not belong in the central dispatcher.

## Required behavior

- `validate` must reject missing configuration, unsupported combinations, or unavailable backend prerequisites before activation.
- `start` must return non-zero when the backend cannot establish its listener or otherwise enter its usable state.
- `stop` should be idempotent and must not terminate resources owned by an unrelated profile.
- `status` should return zero only when the backend is usable from the agent's point of view.
- `endpoint` must return the canonical proxy endpoint used by the control plane.
- `managed` returns zero when proxy-agent owns the backend process and is responsible for identifying/stopping it.
- `pid` returns the currently-owned backend PID only after ownership/identity verification.
- `process_identity` returns a concise, non-secret identity string for machine-readable runtime state.
- Backends must not assume a fixed installation path, server IP, username, or home directory.
- Security-sensitive defaults belong in the backend implementation and configuration validation.

## Current backends

`ssh-socks` establishes a local SOCKS5 listener using OpenSSH dynamic forwarding and AutoSSH. It is managed by proxy-agent, advertises `socks5`, `dynamic_dns`, and `stream_proxy`, and uses a profile-local PID file plus command-line identity verification for lifecycle ownership.

`local-endpoint` adopts an already-running HTTP or SOCKS endpoint. It is explicitly unmanaged; its start/stop contract validates or probes the endpoint but never kills the external proxy process.

The loader intentionally uses the filename as the extension boundary so adding a future backend does not require changing the central lifecycle switch.
