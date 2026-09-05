# 0.4 Upgrade Transaction Gate

`upgrade.sh` and `upgrade-user.sh` are lifecycle transactions. They acquire the same per-runtime lifecycle lock used by the reconciler before checking service state, taking backups, stopping the service, installing, validating, and restoring the previous state on failure.

Transaction invariant:

```text
acquire lifecycle lock
    ↓
backup program/config/service state
    ↓
stop only when previously active
    ↓
install candidate
    ↓
validate candidate
    ├─ PASS → restore the previous active/stopped state
    └─ FAIL → restore program/config/service files and previous active state
    ↓
release lifecycle lock
```

The lock is held for the whole transaction so a concurrent upgrade or reconciler activation cannot interleave with the installation/rollback window.

The CI gate is intentionally independent from the existing smoke suite and must pass before treating upgrade transaction behavior as release-ready.

Real backend validation remains a separate gate; a skipped real-backend workflow is not treated as a pass.
