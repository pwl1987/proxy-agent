# Rootless operator deployment

`install-user.sh` provides a user-scoped deployment that does not require root or a system service account.

## Files and paths

The rootless installation uses:

- executables: `$HOME/.local/bin` by default
- application tree: `$HOME/.local/lib/proxy-agent` by default
- configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/proxy-agent`
- profiles: `${XDG_CONFIG_HOME:-$HOME/.config}/proxy-agent/profiles`
- interactive runtime state: `${XDG_RUNTIME_DIR:-$HOME/.cache/proxy-agent}/run`
- interactive logs: `${XDG_STATE_HOME:-$HOME/.local/state}/proxy-agent/log`

`PREFIX`, `BIN`, and `XDG_CONFIG_HOME` can be overridden for non-standard layouts.

## Install

Run from a checkout:

```bash
./install-user.sh
```

Then edit the generated configuration and validate it:

```bash
$EDITOR "${XDG_CONFIG_HOME:-$HOME/.config}/proxy-agent/proxy-agent.conf"
proxy-ctl validate
proxy-ctl doctor
proxy-ctl start
proxy-ctl status --json=v2
```

The installer never overwrites an existing user configuration.

## User systemd

When a user systemd manager is available, the installer reloads it and enables `proxy-agent.service`. The installed templates also provide `proxy-agent@.service` and corresponding health services/timers.

```bash
systemctl --user start proxy-agent.service
systemctl --user status proxy-agent.service
systemctl --user enable --now proxy-agent-health.timer
```

Profile:

```bash
systemctl --user enable --now proxy-agent@office.service
systemctl --user enable --now proxy-agent-health@office.timer
```

User services deliberately keep runtime state and logs under `%t` so `ProtectHome=read-only` can remain enabled.

For machines that need the user service to survive logout and start at boot, a system administrator can enable systemd lingering for the user. The proxy-agent installer itself does not require root to do this.

## SSH backend

The SSH private key must be readable by the user running the rootless agent. The backend still enforces strict host-key verification by default and profile-safe process ownership.

## System deployment vs rootless deployment

Use `install.sh` for a host-wide system service under the dedicated `proxy-agent` account. Use `install-user.sh` when the operator should own the full installation and no privileged service account is desired.
