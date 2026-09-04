# TUI

`proxy-ctl tui` provides the interactive operator console for proxy-agent.

The TUI is intentionally optional and dependency-light. The core agent remains usable without it; the TUI only requires an interactive terminal and `tput`.

## Controls

| Key | Action |
|---|---|
| `s` | Start backend and adapters |
| `x` | Stop backend and adapters |
| `r` | Restart the proxy stack |
| `t` | Run configured connectivity tests |
| `d` | Run diagnosis |
| `i` | Show application integration commands |
| `R` | Query routing policy for a hostname or IPv4 address |
| `p` | Switch active profile without exiting the TUI |
| `Enter` | Refresh |
| `q` | Quit |

## Profiles

The TUI starts with the profile selected through `PA_PROFILE` or `--profile NAME`. Press `p` to select another named profile from `PA_PROFILE_DIR`; choosing `default` returns to the base configuration.

Each profile reuses the same `proxy-ctl` lifecycle, endpoint, health, and diagnostic semantics. Profile state is isolated under the configured state directory.

## Design boundary

The TUI never implements proxying itself. It calls the same `proxy-ctl` command paths used by automation, so interactive and scripted operations share one control plane.

For terminals without reliable Unicode box-drawing support, the implementation remains functional but may render the borders imperfectly. This is preferred over introducing a mandatory UI framework or compiled dependency into the agent core.
