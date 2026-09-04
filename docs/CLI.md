# CLI reference

## Core lifecycle

```text
proxy-ctl start
proxy-ctl stop
proxy-ctl restart
proxy-ctl status
```

## Verification

```text
proxy-ctl test
proxy-ctl diagnose
proxy-ctl doctor
proxy-ctl route <host-or-ip>
```

## Environment

```bash
eval "$(proxy-ctl env)"
eval "$(proxy-ctl env --off)"
```

## Application integration

```text
proxy-ctl integration git
proxy-ctl integration docker
proxy-ctl integration pip
proxy-ctl integration npm
proxy-ctl integration all
```

## Interactive operations

```text
proxy-ctl tui
```

The TUI is an operator interface over these same CLI operations rather than a separate implementation of the proxy lifecycle.
