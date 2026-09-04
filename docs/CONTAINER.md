# Container deployment

`proxy-agent` can run as a single foreground process in a container. The container image deliberately does not start systemd; the container runtime owns process supervision and restart policy.

## Build

```bash
docker build -f Containerfile -t proxy-agent:0.2.0 .
```

The image runs as the dedicated non-root `proxy-agent` user. `proxy-ctl run` is the container entrypoint.

## Configuration

Mount the production configuration over `/etc/proxy-agent/proxy-agent.conf`:

```bash
docker run --rm \
  -p 127.0.0.1:1080:1080 \
  -v "$PWD/proxy-agent.conf:/etc/proxy-agent/proxy-agent.conf:ro" \
  proxy-agent:0.2.0
```

Keep the mounted configuration owner-readable and not world-readable. For SSH-based backends, mount the private key read-only into the service user's home and reference that path from the configuration.

## Network model

The image does not publish a proxy port automatically. Publishing `1080` is an explicit deployment decision. The default configuration continues to bind the SOCKS listener to loopback inside the container; for container-to-host or service-to-service access, configure the listener intentionally and enforce access control at the container/network layer.

For Kubernetes or another orchestrator, use the container healthcheck as a basic liveness signal and use `HEALTH_TARGETS` with `HEALTH_NETWORK_REQUIRED=true` when end-to-end upstream reachability is part of the workload SLO.

## Upgrade

Treat the image tag/digest as the release boundary. Build a new image from the reviewed repository commit, validate the configuration in the new image, then roll the workload using the orchestrator's normal replacement strategy.

Do not run `install.sh` or `systemd` units inside the container. Those are host deployment concerns. Rootless host deployment uses `install-user.sh`; container deployment uses `Containerfile` and the container runtime.
