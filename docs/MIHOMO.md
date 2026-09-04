# Mihomo Backend

`proxy-agent` supports Mihomo as a managed backend without taking ownership of Mihomo's YAML schema.

Configure the agent with:

```bash
BACKEND="mihomo"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"
MIHOMO_BIN="mihomo"
MIHOMO_CONFIG="~/.config/mihomo/config.yaml"
```

The Mihomo configuration must itself expose a SOCKS-compatible listener at `SOCKS_BIND:SOCKS_PORT`. `proxy-agent` does not rewrite `mixed-port`, `socks-port`, routing rules, DNS, proxy providers, or proxy groups.

## Lifecycle contract

The backend validates the config with Mihomo's native `-t -f <config>` check, starts `mihomo -f <config>`, verifies the expected executable/UID/config command line, and verifies that the declared listener belongs to the process before declaring the backend live.

`status` is liveness-oriented. End-to-end network reachability is handled by `proxy-agent-health` through `HEALTH_TARGETS` and is intentionally separate from process/listener liveness.

## Security

`MIHOMO_CONFIG` must be owner-readable and must not be group/other-readable or writable by group/others. The backend never kills a process unless executable, UID, command line, and listener ownership all match the active profile.

Mihomo's own YAML remains the source of truth for its advanced routing and protocol capabilities. `proxy-agent` currently advertises only the generic capabilities it can guarantee from the declared SOCKS endpoint: `socks5` and `stream_proxy`.
