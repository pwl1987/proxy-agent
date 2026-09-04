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

**Health** probes the active proxy path and can perform controlled recovery. Health state is persisted under the selected profile state directory and reflected into runtime state JSON.

**Profile** selects a complete independent configuration. Profile services and health timers are separately addressable through `proxy-agent@<profile>` and `proxy-agent-health@<profile>`.

## Backend contract

A backend named `foo-bar` is loaded from `backends/foo-bar.sh` and must expose:

```text
backend_foo_bar_validate()
backend_foo_bar_start()
backend_foo_bar_stop()
backend_foo_bar_status()
backend_foo_bar_endpoint()
backend_foo_bar_managed()
backend_foo_bar_pid()
backend_foo_bar_process_identity()
```

Capability metadata is exposed through corresponding backend capability functions. The control plane does not switch on backend implementation details for normal lifecycle, endpoint, or integration operations.

`managed=true` means proxy-agent owns the backend process and may identify and stop it. An unmanaged backend, such as `local-endpoint`, represents an externally-owned service and must not terminate it.

## Runtime lifecycle

`proxy-ctl start` is a one-shot activation operation: it validates configuration, starts the backend, starts any adapter, records state, and returns. It does not remain attached to the backend process.

`proxy-ctl run` is the service-manager entrypoint. It starts the full stack and remains attached until the managed backend exits or the service is stopped. systemd units therefore invoke `run`, not `start`, and use `KillMode=control-group` to own the control-plane process tree.

Managed backends keep a profile-local PID file and expose a process identity check. A start refuses to take over a listening port that is not owned by the active profile; a stop refuses to kill an unrelated listener.

## Runtime state

The runtime state file is stored at `<state-dir>/runtime.json` and is published as schema v2 through `proxy-ctl status --json=v2`. It contains backend identity/status, adapter status, health timestamps, and lifecycle timestamps. The legacy `status --json` schema v1 remains available for compatibility.

## TUI boundary

The TUI is intentionally not another control implementation. It invokes `proxy-ctl` commands, so a TUI action and a shell automation action reach the same code path.
