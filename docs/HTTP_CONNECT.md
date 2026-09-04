# HTTP CONNECT Backend

`proxy-agent` supports an upstream HTTP proxy as an unmanaged backend. The endpoint is consumed directly by applications; proxy-agent never owns or terminates the upstream proxy process.

```bash
BACKEND="http-connect"
HTTP_CONNECT_PROXY_URL="http://proxy.example.net:3128"
```

The backend advertises `http_native` and `stream_proxy`. It intentionally does not advertise `socks5`, so the Privoxy SOCKS-to-HTTP adapter is not inserted on top of an already HTTP-native upstream.

`status` is endpoint liveness/config validity. End-to-end connectivity is handled by `proxy-agent-health` via `HEALTH_TARGETS`, using the active HTTP proxy endpoint.

Credentials should be handled by the upstream URL only when the deployment explicitly permits that pattern; prefer external credential mechanisms where available. The current validator accepts the generic endpoint syntax but does not expose credentials in process identity output.