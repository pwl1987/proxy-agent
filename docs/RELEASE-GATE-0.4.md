# 0.4.0 Release Gate

Current `0.4.x` baseline is merge commit `6247ae824feb3d93654d5d30e5990ee50973cf19` (PR #29).

## Passing baseline

- Revision store smoke
- Audit lock smoke
- Reconciler smoke
- Reconciler pin smoke
- Health recovery smoke
- Functional smoke suite
- ShellCheck
- Container contract

## Active gate

- Lifecycle concurrency lock: implemented in this branch; dedicated smoke added.
- Reconciler and lifecycle activation now share the same `.lifecycle.lock` boundary.
- State lock stale cleanup/release is owner-safe (PID + `/proc` starttime plus quarantine rename).

## Explicit blockers

- The existing `upgrade.sh` / `upgrade-user.sh` entrypoints still need to join the lifecycle transaction boundary.
- Real backend gate remains `SKIPPED` unless `workflow_dispatch` is run.
- Release performance/history audit remains pending.

`SKIPPED` is never treated as `PASS` for the final release decision.
