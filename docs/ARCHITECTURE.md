# Architecture

proxy-agent is organized as a small Linux control plane rather than a single proxy script.

```text
                       +----------------------+
                       |      proxy-ctl       |
                       | CLI / TUI entrypoint |
                       +----------+-----------+
                                  |
             +--------------------+--------------------+
             |                    |                    |
          Config               Routing             Health
             |                    |                    |
             +--------------------+--------------------+
                                  |
                         Backend interface
                                  |
             +--------------------+--------------------+
             |                                         |
        ssh-socks                               local-endpoint
             |                                         |
           autossh                              existing proxy
             |                                         |
           SOCKS5                              HTTP / SOCKS
             |
       optional adapter
             |
           Privoxy
             |
            HTTP

        Application integrations consume the
        exported endpoint/capability contract.
```

## Core boundaries

**Config** selects the active backend, profile, listeners and policy. Configuration is intentionally declarative shell data and is kept outside the application code.

**Backend** establishes or discovers proxy connectivity and owns backend-specific process details. It does not decide which destinations should be direct or proxied.

**Adapter** exposes one proxy transport in another client-facing protocol. The current example is Privoxy translating HTTP proxy requests into a backend with the `socks5` capability.

**Routing** explains ordered direct/proxy policy. It supports exact, suffix, wildcard and IPv4 CIDR matchers and does not modify the host routing table.

**Integration** emits application-specific configuration for Git, Docker, pip and npm. Integration modules remain side-effect free.

**Health** probes the active proxy path and can perform controlled recovery. Health state is persisted under the selected profile state directory.

**Profile** selects a complete independent configuration. Profile services and health timers are separately addressable through `proxy-agent@<profile>` and `proxy-agent-health@<profile>`.

## Backend contract

The current backend contract is already implemented, not future-only. A backend named `foo-bar` is loaded from `backends/foo-bar.sh` and must expose:

```text
backend_foo_bar_validate()
backend_foo_bar_start()
backend_foo_bar_stop()
backend_foo_bar_status()
backend_foo_bar_endpoint()
```

Capability metadata is exposed through the corresponding backend capability functions. The control plane does not switch on backend implementation details for normal lifecycle, endpoint, or integration operations.

## Lifecycle ownership

Interactive starts may use background backend behavior where appropriate. systemd-managed backends use foreground execution and `KillMode=control-group` so the service owns the backend process tree. External backends such as `local-endpoint` are intentionally unmanaged: proxy-agent probes and describes them but does not attempt to kill their processes.

## TUI boundary

The TUI is intentionally not another control implementation. It invokes `proxy-ctl` commands, so a TUI action and a shell automation action reach the same code path.
