# Backend Contract

Backends live under `backends/<name>.sh` and are loaded dynamically by `proxy-ctl`.

A backend named `foo-bar` must implement the following shell functions:

```bash
backend_foo_bar_start
backend_foo_bar_stop
backend_foo_bar_status
```

It may additionally expose capability metadata through `lib/backend-capabilities.sh` until capability metadata is colocated with the backend.

## Required behavior

- `start` must return non-zero when the backend cannot establish its listener.
- `stop` should be idempotent.
- `status` should return zero only when the backend is usable from the agent's point of view.
- Backends must not assume a fixed installation path, server IP, username, or home directory.
- Security-sensitive defaults belong in the backend implementation and configuration validation.

## Current backend

`ssh-socks` establishes a local SOCKS5 listener using OpenSSH dynamic forwarding and AutoSSH. It advertises `socks5`, `dynamic_dns`, and `stream_proxy` capabilities.

The loader intentionally uses the filename as the extension boundary so adding a future backend does not require changing the central lifecycle switch.
