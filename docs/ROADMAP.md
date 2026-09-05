# Roadmap

## V2 foundation — completed
- SSH → SOCKS5 backend
- Optional HTTP/Privoxy adapter
- Existing local SOCKS/HTTP endpoint backend
- Domain and IPv4 CIDR policy inspection
- Ordered route rules with exact/suffix/wildcard/CIDR matching
- Environment export
- Health checks and controlled recovery
- Git / Docker / pip / npm integration emitters
- Dependency-light operator TUI
- ShellCheck and functional smoke coverage

## V2 control plane — completed
- Formal backend lifecycle contract ✅
- Explicit backend liveness contract ✅
- Formal backend capability contract ✅
- Named proxy profiles ✅
- Profile selection from CLI and TUI ✅
- Per-profile state isolation ✅
- Backend endpoint contract ✅
- Ordered route policy and `route` explanation ✅
- Machine-readable `status --json` schema v1 ✅
- Per-profile systemd services and health timers ✅
- Strict configuration validation and `proxy-ctl validate` ✅

## V2 runtime hardening — completed
- Runtime state schema v2 via `status --json=v2` ✅
- Health markers synchronized into runtime state ✅
- Managed/unmanaged backend ownership contract ✅
- Profile-safe backend PID ownership ✅
- Port collision refusal for managed local listeners ✅
- Long-lived `proxy-ctl run` service-manager entrypoint ✅
- systemd lifecycle no longer depends on foreground backend environment hacks ✅

## V2 deployment hardening — completed
- Dedicated least-privilege systemd service account ✅
- Configuration ownership/mode enforcement ✅
- Runtime/log directory isolation ✅
- systemd `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, and kernel sandboxing ✅
- Generated Privoxy configuration moved into runtime state ✅
- Rootless interactive installation/execution ✅
- Rootless user systemd services ✅
- Reproducible system/rootless upgrade entrypoints with pre-restore validation ✅
- Non-root container runtime based on `proxy-ctl run` ✅

## V2 backend compatibility — completed
- Separate backend liveness from active network health
- Adapter/backend compatibility matrix and contract tests
- SSH SOCKS5
- Existing local SOCKS/HTTP endpoint
- sing-box
- mihomo
- HTTP CONNECT upstream

## V2 release engineering — completed
- Tag-driven release workflow with VERSION/tag consistency gate
- Non-root container build and GHCR publish workflow
- Published image digest capture
- GitHub release generation
- 0.2.0 release baseline merged to `main`
- Container runtime CI execution gate
- Structured operational telemetry and health-history inspection
- Host/container networking deployment patterns
- Upgrade rollback verification and compatibility policy

## V3 control API — completed / baseline
- Typed configuration schema
- Local control API over Unix socket / loopback HTTP
- Desired state vs observed state
- Config revision and optimistic concurrency
- Audit events
- `proxy-ctl exec`
- Capability-versioned backend metadata
- TUI converted from CLI subprocess client to API client

## V4 Web control plane — historical direction
The original roadmap treated Web control as a separate V4 track. The current plan supersedes that sequencing: Web/LAN work is now delivered incrementally inside the 0.5.x evolution line after the Egress Path foundation is stable.

## 0.5.x — architecture evolution line

0.5.x is intentionally split into independently testable releases. The architecture, ownership, state, security and compatibility rules are frozen in `docs/V0.5-ARCHITECTURE.zh-CN.md` and `docs/V0.5-DECISIONS.zh-CN.md`. Individual releases must not silently redefine those contracts.

### 0.5.0 — Egress Path foundation

**Goal:** introduce the smallest reusable path contract without changing existing runtime behavior.

- canonical `egress_path` typed model
- explicit Backend vs Egress Path responsibility boundary
- `direct` transport semantics
- legacy `ssh-socks` configuration remains valid when `egress_path` is absent
- deterministic rejection of conflicting legacy/new target definitions
- typed config → legacy runtime projection remains one-way
- route → egress resolution contract without multi-egress selection
- revision/reconcile integration and focused regression tests

**Must not include:** Web, LAN exposure, Jump Host runtime, secret-provider framework, export/import, draining, failover or balancing.

**Release gate:** all existing 0.4.x smoke/contract suites remain green; new config/revision/reconcile tests prove old profiles behave unchanged.

### 0.5.1 — SSH Jump + Identity + Path Health

**Goal:** make Egress Path operational for the one-hop SSH topology.

- Local → Jump → Target
- separate Jump/Target `identity_ref`
- `known_hosts_ref` and host-key verification policy
- initial secret/reference resolver (file-backed where appropriate)
- transport/jump/target path health with causal reason/evidence
- explicit `dns_mode: local|remote`
- preserve current `ssh-socks` remote-DNS behavior by default
- bounded diagnostic/recovery hooks without infinite restart loops

**Must not include:** Web, LAN management, multi-hop DSL, automatic failover/balancing.

**Release gate:** direct and jump paths have deterministic validation, failure diagnosis and cleanup; no leaked process/listener state; old direct SSH profiles remain compatible.

### 0.5.2 — Web/LAN Management Plane

**Goal:** expose the stable control/data-plane contracts through a secure remote management surface.

- authenticated HTTPS Web Gateway
- Web uses Control API v1; no parallel revision/audit/reconcile/lifecycle logic
- explicit management listener and LAN ACL
- session lifecycle, CSRF, login-rate-limit, secure cookie/token handling
- one Admin role
- profile/backend/egress configuration UI
- validate → diff → apply with optimistic concurrency
- health/event/revision views
- remote mutation audit durability semantics
- Web Gateway → protected local Control API access boundary

**Must not include:** public SOCKS/HTTP as a shortcut for management, full RBAC, SSO/OIDC, or universal zero-downtime activation.

**Release gate:** security tests, concurrent-edit conflict tests, audit-failure tests, and system/rootless/container deployment tests for supported modes.

### 0.5.3 — Recovery / Operations

**Goal:** make configuration recovery and operational diagnosis safe and reproducible.

- canonical configuration/revision export/import
- validate → compatibility check → revision → explicit apply recovery flow
- no private-key material in exports
- richer diagnostics/event visibility
- upgrade/downgrade compatibility documentation and tests
- LAN deployment/integration coverage
- bounded recovery state and operator-visible terminal reasons

**Release gate:** failed imports cannot activate; recovery cannot bypass revision/audit/lifecycle boundaries; supported upgrade/restore paths are tested.

### 0.5.4+ — Advanced Runtime

**Goal:** add complexity only after the single-path model has proven stable.

- connection draining behind explicit backend capability
- multiple named Egress Paths
- route → Egress selection as a separate decision layer
- future `EgressGroup`
- health-driven failover/balancing only after explicit selection/failure/stickiness/retry semantics and tests

**Release gate:** every advanced capability is opt-in/capability-gated and has deterministic failure, recovery, concurrency and observability semantics.

## 0.5.x cross-release invariants

These rules apply to every 0.5.x release:

- typed configuration/revision is the canonical source of truth
- legacy configuration is a runtime compatibility projection only
- Profile remains the isolation boundary
- Control API v1 remains the common control contract unless a true breaking change requires a new version
- `current_revision`, `desired_revision`, and `observed_revision` keep their existing meanings
- stale mutations remain conflicts; no silent last-write-wins
- existing revision/audit/lifecycle/upgrade locks are reused; Web does not create a bypass path
- `runtime.json` and `runtime/reconcile-state.json` remain distinct state layers even when API responses aggregate them
- `unknown` is never silently converted into `failed` or `healthy`
- health records causal evidence where possible
- self-healing is bounded, observable and resettable; no unbounded restart loop
- Web never edits runtime/revision files or directly controls backend processes
- no private key material in API responses, revisions, audit or exports
- new capabilities are feature-gated by explicit backend capability metadata
- old supported 0.4.x profiles remain runnable on supported 0.5.x releases
- forward compatibility is not assumed; downgrade requires explicit compatibility handling
- system/rootless/container support is part of every relevant release gate
- no traffic disguise, censorship/DPI evasion, or universal zero-downtime promises

## V5 Cross-platform — planned
- macOS runtime adapter (`launchd`)
- Windows runtime adapter (Windows Service)
- platform-specific installers
- Linux / macOS / Windows CI matrix
- shared control API and identical CLI semantics
- container runtime retained as a universal deployment path

## V6 Production control-plane — target
- versioned stable API
- versioned/atomic installation tree
- metrics endpoint
- signed/provenance-backed release artifacts
- SBOM and image attestation
- fleet-ready configuration export
- compatibility policy for old configuration revisions

## Architecture rule

Do not continue adding large amounts of imperative behavior directly to `proxy-ctl`. Keep the current Shell implementation as the Linux reference implementation while introducing typed configuration and a local control API. Replace the implementation language only after the behavioral contract is frozen.

The 0.5.x evolution follows the same rule: define domain/control contracts first, reuse the existing revision/audit/reconcile/backend lifecycle machinery, keep state ownership explicit, and avoid parallel sources of truth or parallel state machines.
