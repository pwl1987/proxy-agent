# 0.4 Lifecycle Transaction Boundary

`0.4.x` lifecycle mutations share one per-profile `.lifecycle.lock`.

The lock is an advisory OS file lock (`flock` on Linux and `fcntl.flock` in the reconciler). It serializes lifecycle mutation entrypoints that participate in the control plane and prevents reconciler activation from racing a lifecycle operation.

The lower-level `.state.lock` remains a separate state-file mutation lock. Its owner metadata uses PID plus `/proc/<pid>/stat` starttime. Stale cleanup uses quarantine rename; release verifies that the current process still owns the lock before removing it.

The lifecycle lock is not a replacement for revision/audit locks. The intended hierarchy is:

```text
control operation
    |
    +-- lifecycle lock
    |       |
    |       +-- backend / adapter mutation
    |       +-- observed-state update
    |
    +-- revision/audit transaction locks
```

Upgrade must eventually acquire the same lifecycle boundary before stopping/restarting a service. Until the upgrade entrypoints are migrated, real-backend and upgrade transaction gates remain release blockers.
