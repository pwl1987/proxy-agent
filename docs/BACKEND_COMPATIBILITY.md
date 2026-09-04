# Backend Compatibility Contract

`proxy-agent` treats backend lifecycle and network health as separate concerns. Every backend exposes the same semantic surface; ownership determines whether lifecycle operations may create or terminate a process.

| Contract | SSH SOCKS5 | local endpoint | sing-box | mihomo | HTTP CONNECT |
|---|---:|---:|---:|---:|---:|
| `validate` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `start` | ✅ | no-op | ✅ | ✅ | no-op |
| `stop` | ✅ | no-op | ✅ | ✅ | no-op |
| `liveness` | process + listener | local listener / remote endpoint boundary | process + declared listener | process + declared listener | configured upstream endpoint |
| `status` | endpoint status | network-capable status | endpoint status | endpoint status | upstream/network-capable status |
| `endpoint` | `socks5h://` | configured URL | `socks5h://` | `socks5h://` | `http://` or `https://` |
| `managed` | ✅ | ❌ | ✅ | ✅ | ❌ |
| `pid` | ✅ | ❌ | ✅ | ✅ | ❌ |
| `process_identity` | ✅ | ❌ | ✅ | ✅ | ❌ |
| capabilities | `socks5`, `stream_proxy` | inferred from URL | `socks5`, `stream_proxy` | `socks5`, `stream_proxy` | `http_native`, `stream_proxy` |

## Health semantics

`proxy-agent-health` first evaluates backend `liveness`. It evaluates active network targets separately through `HEALTH_TARGETS`.

`HEALTH_NETWORK_REQUIRED=false` means an Internet probe failure does not by itself turn a live backend into an unhealthy backend. Set it to `true` when end-to-end reachability is part of the service SLO.

Liveness never means “the Internet works”. It means the backend resource proxy-agent is responsible for is present and plausibly usable according to that backend's ownership model.

For unmanaged remote endpoints, proxy-agent cannot safely infer process ownership. Local loopback endpoints can be checked for a listening socket; remote endpoint reachability belongs to the network-health layer.

## Adapter compatibility

The Privoxy adapter requires `socks5`. HTTP-native backends are exposed directly through `HTTP_PROXY`/`HTTPS_PROXY` and do not require Privoxy.

This makes adapter selection capability-driven rather than backend-name-driven:

- `socks5` → SOCKS-consuming applications and optional Privoxy conversion;
- `http_native` → direct HTTP proxy consumers;
- `stream_proxy` → generic stream-oriented proxy path.

## Managed backends

Managed backends must prove process ownership before stopping or reporting process state. The ownership identity includes the expected executable/configuration relationship and listener where applicable. A stale PID alone is never sufficient authority to terminate a process.

## sing-box and mihomo boundaries

The sing-box and mihomo adapters deliberately do not translate their native JSON/YAML configuration into the proxy-agent shell configuration model. The operator-owned native configuration remains the source of truth. proxy-agent validates the native configuration with the backend's own command where available, starts/stops the backend, verifies ownership, and exposes the declared local proxy endpoint.

## HTTP CONNECT boundary

The HTTP CONNECT backend is an unmanaged upstream endpoint. proxy-agent does not spawn, stop, or rewrite the remote proxy. It validates the URL, exports the HTTP-native endpoint, and leaves end-to-end reachability to the network-health layer.
