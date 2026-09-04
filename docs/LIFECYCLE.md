# Lifecycle Model

`proxy-agent` separates control-plane commands from backend process ownership.

- Interactive `proxy-ctl start` keeps historical background behavior for the active backend.
- systemd runs `proxy-ctl start` with `PA_FOREGROUND=true` so the backend remains attached to the service cgroup.
- `ssh-socks` honors `PA_FOREGROUND=true` by omitting autossh's background flag.
- `KillMode=control-group` ensures the backend process tree is terminated with the service.
- Adapter processes remain subordinate to the same control path.

This model is intentionally backend-driven: future managed backends should expose a foreground mode when systemd owns their lifecycle. External `local-endpoint` remains unmanaged by design; proxy-agent only probes and describes it.
