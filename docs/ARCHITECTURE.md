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
               +----------------+----------------+
               |                                 |
          ssh-socks                         future backends
               |
            autossh
               |
            SOCKS5
               |
          +----+----+
          |         |
      direct API   optional adapter
                    |
                  Privoxy
                    |
                  HTTP

        Application integrations consume the exported
        proxy contract without owning backend details.
```

## Core boundary

**Backend** establishes connectivity and owns backend-specific process details. It does not decide which applications or destinations should use the proxy.

**Adapter** exposes one proxy transport in another client-facing protocol. The current example is Privoxy translating HTTP proxy requests into the local SOCKS5 backend.

**Routing** explains direct/proxy policy. The current CLI implementation provides domain and IPv4 CIDR policy diagnostics; it does not modify the host routing table.

**Integration** emits application-specific configuration for Git, Docker, pip, and npm. Integration modules should remain side-effect free until an explicit future apply mode is introduced.

**Health** probes the active proxy path and can perform one controlled recovery restart. Health state is persisted as timestamp markers under the state directory.

## TUI boundary

The TUI is intentionally not another control implementation. It invokes `proxy-ctl` commands, so a TUI action and a shell automation action reach the same code path. This keeps operational behavior consistent and makes the TUI disposable.

## Future backend contract

A backend should eventually expose these semantic operations:

```text
validate()
start()
stop()
status()
endpoint()
capabilities()
```

`proxy-ctl` should select a backend by name, while adapters and integrations consume the resulting local endpoint rather than knowing how it was created.
