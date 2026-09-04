# Control Plane

The control plane is now backend-neutral.

## Runtime contract

Every managed backend exposes:

`validate`, `start`, `stop`, `status`, `endpoint`, `capabilities`.

`proxy-ctl` consumes that contract without branching on a specific backend for normal lifecycle operations.

## Status contract

`proxy-ctl status --json` emits schema version 1 with the active profile, backend, endpoint, backend state, and optional HTTP adapter state. Consumers should use `schema_version` before interpreting fields.

## Routing contract

`ROUTE_RULES` is ordered by numeric priority. The first matching `DIRECT` or `PROXY` rule wins; legacy domain/CIDR lists remain a compatibility fallback.

## Ownership

Managed backends must support a foreground execution mode when run under systemd. The service uses `PA_FOREGROUND=true`, `Type=simple`, and `KillMode=control-group`. Unmanaged backends such as `local-endpoint` are intentionally probe-only.
