# Backend Compatibility Contract

`proxy-agent` treats backend lifecycle and network health as separate concerns.

| Contract | Meaning | SSH SOCKS5 | local endpoint | sing-box |
|---|---|---:|---:|---:|
| `validate` | Static/runtime prerequisites are acceptable | ✅ | ✅ | ✅ |
| `start` | Bring owned backend into service | ✅ | ✅ no-op | ✅ |
| `stop` | Stop only resources owned by the backend | ✅ | ✅ no-op | ✅ |
| `liveness` | Process/listener readiness without probing an Internet target | ✅ | ✅ local listener / configured remote | ✅ |
| `status` | Current endpoint service status; may include backend-specific checks | ✅ | ✅ network-capable status | ✅ |
| `endpoint` | Stable proxy endpoint consumed by adapters/integrations | ✅ | ✅ | ✅ |
| `managed` | Whether proxy-agent owns the process | ✅ | ❌ | ✅ |
| `pid` | Owned process identity, when managed | ✅ | ❌ | ✅ |
| `process_identity` | Human/machine-readable ownership identity | ✅ | ❌ | ✅ |
| capabilities | Adapter-facing feature set | SOCKS5 | SOCKS5/HTTP | SOCKS5 |

## Health semantics

`proxy-agent-health` first evaluates backend `liveness`. It evaluates active network targets separately through `HEALTH_TARGETS`.

`HEALTH_NETWORK_REQUIRED=false` means an Internet probe failure does not by itself turn a live backend into an unhealthy backend. Set it to `true` when end-to-end reachability is part of the service SLO.

For an unmanaged remote `local-endpoint`, proxy-agent cannot safely infer process ownership. Local loopback endpoints are checked for a listening socket; remote endpoint reachability belongs to the network-health layer.

## Adapter compatibility

The Privoxy adapter requires the backend to expose `socks5`. HTTP-native backends can be added later without changing lifecycle semantics.

## sing-box boundary

The sing-box backend intentionally does not translate sing-box's JSON configuration into the proxy-agent shell configuration model. `SING_BOX_CONFIG` points to an operator-owned JSON configuration; proxy-agent validates it with the installed `sing-box check` command, then owns only process lifecycle and the declared local SOCKS listener.

Current upstream sing-box documentation defines JSON configuration and the `sing-box check` command, and SOCKS inbounds expose a local SOCKS4/4a/5 server. The repository currently has a 1.13.x stable line and 1.14.x pre-release line; proxy-agent therefore avoids hard-coding version-specific configuration fields in this adapter.
