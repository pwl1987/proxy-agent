# Profiles

Profiles let one proxy-agent installation keep multiple independent proxy endpoints. A profile is a complete configuration file under `PA_PROFILE_DIR` (default `/etc/proxy-agent/profiles`).

## Layout

```text
/etc/proxy-agent/
├── proxy-agent.conf
└── profiles/
    ├── office.conf
    ├── overseas.conf
    └── ci.conf
```

Profile names are limited to letters, numbers, `.`, `_` and `-`.

## Commands

```bash
proxy-agent-profile list
proxy-agent-profile show office
proxy-agent-profile path office
```

Use a profile with any `proxy-ctl` operation:

```bash
proxy-ctl --profile office status
proxy-ctl --profile office test
proxy-ctl --profile overseas route github.com
proxy-ctl --profile ci env
```

The profile state directory is isolated below `PA_STATE_DIR/<profile>`, so health markers from one profile do not overwrite another profile's state.

## Design rule

Profiles are configuration selection, not a second control plane. The same backend loader, adapters, routing engine, health checks and integrations are used regardless of the selected profile.
