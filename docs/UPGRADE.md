# Upgrade workflow

`proxy-agent` supports reproducible upgrades from a checked-out source tree. The installer remains the single implementation of file placement; the upgrade entrypoints add service-state preservation around it.

## System deployment

From the source tree:

```bash
sudo ./upgrade.sh
```

The default paths are:

- install: `/opt/proxy-agent`
- config: `/etc/proxy-agent/proxy-agent.conf`
- profiles: `/etc/proxy-agent/profiles`

The upgrade flow:

1. verify it is running as root;
2. verify an existing configuration is present;
3. remember whether the configured system service is active;
4. stop the service when active;
5. run the normal `install.sh` deployment;
6. reload systemd;
7. restore the service only when it was active before the upgrade;
8. run `proxy-ctl validate` against the preserved configuration.

The existing configuration is not replaced by the installer.

## Rootless deployment

From the source tree:

```bash
./upgrade-user.sh
```

The default paths are:

- install: `$HOME/.local/lib/proxy-agent`
- config: `$HOME/.config/proxy-agent/proxy-agent.conf`
- profiles: `$HOME/.config/proxy-agent/profiles`
- executables: `$HOME/.local/bin`

The user upgrade follows the same active-state preservation rules using `systemctl --user` when a user systemd manager is available.

## Release discipline

Use a clean, reviewed source tree for production upgrades. Do not copy a single script into a running installation and mix files from different revisions. The release revision is identified by the repository `VERSION` file and the Git commit used for the upgrade.

Before a production rollout, run:

```bash
./tests/smoke.sh
./tests/rootless-smoke.sh
./tests/backend-contract-smoke.sh
```

Then run the appropriate upgrade entrypoint and validate the target configuration.

## Configuration safety

Never place secrets into the repository example configuration. Existing production configuration and profiles are deliberately preserved across upgrades. The loader continues to enforce ownership and mode checks before configuration is evaluated.
