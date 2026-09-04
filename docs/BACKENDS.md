# Backend Contract

Backends live under `backends/<name>.sh` and are loaded dynamically by `proxy-ctl`.

A backend named `foo-bar` must implement the following shell functions:

```bash
backend_foo_bar_validate
backend_foo_bar_start
backend_foo_bar_stop
backend_foo_bar_status
backend_foo_bar_endpoint
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
- Backends must not assume a fixed installation path, server IP, username, or home directory.
- Security-sensitive defaults belong in the backend implementation and configuration validation.

## Current backends

`ssh-socks` establishes a local SOCKS5 listener using OpenSSH dynamic forwarding and AutoSSH. It advertises `socks5`, `dynamic_dns`, and `stream_proxy` capabilities.

`local-endpoint` adopts an already-running HTTP or SOCKS endpoint. It deliberately does not own or kill the external proxy process; its lifecycle is configuration validation plus endpoint health probing.

The loader intentionally uses the filename as the extension boundary so adding a future backend does not require changing the central lifecycle switch.
