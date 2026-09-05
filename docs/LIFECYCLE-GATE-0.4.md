# 0.4 Lifecycle Gate Status

Baseline: `0.4.x` at PR #29 merge commit `6247ae824feb3d93654d5d30e5990ee50973cf19`.

This branch adds a shared per-profile lifecycle lock, makes reconciler activation use that same lock, and hardens the lower-level state lock with owner verification and quarantine cleanup.

Release blockers that remain explicit: upgrade entrypoints have not yet joined the lifecycle lock; real backends are still conditional on manual workflow dispatch; final performance/history audit is pending.
