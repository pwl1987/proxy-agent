# Runtime State

`proxy-agent` publishes runtime state at `<profile-state>/runtime.json` through:

```bash
proxy-ctl status --json=v2
```

The legacy `proxy-ctl status --json` schema v1 remains available for existing consumers.

## Schema v2

```json
{
  "schema_version": 2,
  "profile": "default",
  "backend": {
    "name": "ssh-socks",
    "status": "ready",
    "endpoint": "socks5h://127.0.0.1:1080",
    "managed": true,
    "pid": 1234,
    "identity": "autossh:1234 exe=autossh uid=1001 remote=proxy@example.net:22 socks=127.0.0.1:1080"
  },
  "adapter": {
    "type": "privoxy",
    "enabled": true,
    "status": "ready"
  },
  "health": {
    "last_healthy": 1750000000,
    "last_unhealthy": null,
    "last_recovered": null
  },
  "lifecycle": {
    "started_at": 1750000000,
    "last_transition": 1750000000
  }
}
```

Timestamps are Unix epoch seconds or `null`. The identity field must not contain credentials or private key material.

Consumers should branch on `schema_version` and ignore unknown object members so additive v2 fields remain backward-compatible. The v1 schema is intentionally retained instead of silently changing its shape.

The state writer uses a profile-local atomic lock and writes a temporary file before replacing `runtime.json`. A stale lock created by a dead process is eligible for cleanup.
