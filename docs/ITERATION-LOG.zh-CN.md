# 功能迭代日志

> 本文件记录每个版本的实际功能演进、架构边界、验证门禁与发布治理状态。内容以仓库真实代码、PR、Tag 与 CI 结果为依据，不把计划误记为已完成能力。

## 记录规则

每次功能版本收口至少记录：

- 版本与基线：实际分支、基线提交与 Tag。
- 功能增量：进入代码的真实能力，以及对应模块/调用链。
- 状态变化：revision / desired / observed、runtime health、锁与并发边界是否变化。
- 兼容性：对上一版本行为的保持、迁移与显式拒绝。
- 验证结果：CI、Smoke、Functional、ShellCheck、Upgrade Transaction Gate 等实际结果。
- 发布物：Tag、GitHub Release、GHCR 镜像及 provenance 信息。
- 未完成项：明确记录仍处于下一版本的能力，避免把 main 上的预研代码倒灌进稳定版本。

## 0.4.x — 生命周期与控制面收口

### 已落地功能

- `proxy-ctl` 生命周期命令串行化，并以生命周期锁作为权威并发边界。
- Revision Store / Audit Store / Reconciler 的职责边界继续保持单一状态来源。
- Health Recovery 与功能型 smoke 门禁纳入 CI。
- Control API、容器、systemd、rootless installer 等既有契约持续回归。

### 架构边界

生命周期并发控制没有引入第二套状态机；revision、audit、reconcile 与 runtime 状态仍通过既有边界协同。

### 验证

相关 lifecycle gate、revision store、audit lock、reconciler、health recovery 与 functional smoke 均纳入发布门禁。

## 0.5.0 — Egress Path Foundation

### 功能增量

- 引入 typed `egress_path`，支持单一 direct SSH path。
- typed schema 经 `lib/typed-legacy-export.py` 投影为现有 `REMOTE_HOST/REMOTE_USER/REMOTE_PORT`。
- `ssh-socks` 保持既有生命周期、PID、listener、AutoSSH keepalive、strict host-key 与 cleanup 所有权。
- 在 revision / reconcile / Control API 边界内接入 path 变化，不新建 parallel state store。

### 明确非目标

SSH Jump Host、Web/LAN management、自动 failover、multi-egress selection、secret-provider framework 与 export/import 不属于 0.5.0。

### 真实代码调用链

```text
typed config
  -> lib/typed-legacy-export.py
  -> legacy runtime .conf
  -> proxy-ctl validation/lifecycle
  -> backends/ssh-socks.sh
  -> runtime/health state
  -> revision/reconcile/Control API
```

## 0.5.1 — SSH Jump / Identity / Path Health

### 功能增量

- 增加 one-hop SSH Jump path foundation。
- `backend_health_detail` 形成可选 backend health detail contract。
- ssh-socks health 明确拆分 `transport/jump/target/proxy/overall`，并记录 `reason` 与 `last_checked`。
- Jump 不可达时，状态表达为 `jump=failed / target=unknown`，避免将跳板链路故障误报为目标主机故障。
- `runtime.json` status v2 纳入 `health.path`。
- `health-history` 保存因果 reason。
- Status query 保持只读，不主动 probe SSH；health runner 承担 probe 与 observation sync。
- 增加 `path-health-smoke.sh` 与对应 CI 门禁。

### 状态与调用链

```text
health runner
  -> backend health probe
  -> backend_health_detail
  -> runtime status v2 / health.path
  -> health-history causal reason
  -> Control API status read
```

### 验证

Path Health smoke、Functional、ShellCheck、Upgrade Transaction Gate 以及既有 0.4.x 回归均通过后，形成 0.5.1 release candidate 基线。

## 0.5.2 — Web/LAN Management Plane

### 已进入代码

- `bin/proxy-agent-web` authenticated Web Gateway。
- 默认 loopback listener；非 loopback 强制 TLS。
- `PA_WEB_ALLOW_CIDRS` / `--allow-cidr` 实现显式管理面源地址 ACL；ACL 在 healthz、静态 UI、session 与 Control API proxy 之前生效。
- Gateway 通过 Unix socket 调用现有 Control API v1，不直接拥有 revision/audit/runtime/reconcile 状态。
- 已有 read-only GET facade、`no-store` 响应与 mutation route allowlist。

### 已落地：Session / CSRF / Login Rate Limit

- admin token file 作为 bootstrap credential。
- 登录成功生成随机 session id + CSRF token。
- session 默认 30 分钟、最多 256 个，并仅驻留进程内存；Gateway 重启后失效，不引入持久 Web 状态。
- cookie 使用 `HttpOnly`、`SameSite=Strict`；TLS listener 增加 `Secure`。
- 所有 Web POST 控制操作要求 session + `X-CSRF-Token`，并校验 Origin/Referer。
- 登录失败按 peer IP 进行 60 秒窗口 5 次失败限流，超限返回 429。
- Web POST 已接到既有 Control API v1 的 validate/revisions/apply/rollback/runtime 路由，不复制其 validation、revision、audit、activation、reconcile 逻辑。
- `tests/web-gateway-smoke.sh`、`tests/web-auth-audit-smoke.sh` 覆盖 session、CSRF、rate limit、control proxy、TLS listener boundary、logout、Profile discovery 与审计边界。

### 已落地：Configuration Management UI

- `web/index.html` 提供 authenticated typed configuration editor。
- `bin/proxy-agent-web-ui` 复用现有 Gateway 的 session、CSRF、rate-limit、ACL 与 Unix-socket Control API 边界。
- `web/config-form.js` 已支持 `ssh-socks`、`local-endpoint`、`sing-box`、`mihomo`、`http-connect` Backend，以及 SSH direct/jump Egress Path、DNS mode、listeners、health、SSH host-key checking。
- `web/profile-selector.js` 通过只读 `GET /api/v1/profiles` 发现 profile 名称，空值继续表示默认 profile。
- `web/config-form-sync.js` 修复异步 `loadState()` 更新 typed JSON 后结构化表单不自动同步的问题，保持现有 `form-load` 逻辑为唯一字段映射源。
- 页面支持 runtime/health/revision 概览、typed JSON 编辑、Validation、结构化 Diff、Revision 创建与 Apply。
- `create revision` 使用 `if_match_revision`，并发变化由 Control API 返回 409；UI 不实现第二套 revision head。
- Apply 使用新建 revision 作为 optimistic-concurrency 边界，并继续委托既有 reconcile。
- `web/events-view.js` 消费现有 `GET /api/v1/events`，只读显示最近审计事件，不直接读 Audit Store。
- `bin/proxy-agent-api-auth` 对 `actor=web-ui` 的 remote mutation 增加 durable admission audit：审计无法提交时返回 `503 audit_unavailable`，不向核心 Control API 转发；本地 Control API 的 `safe_audit()` best-effort 兼容语义保持不变。
- `Containerfile` 显式打包 `web/`。
- CI 的 Web UI syntax gate 已覆盖 `config-form.js`、`profile-selector.js`、`config-form-sync.js`、`events-view.js` 等 Web JavaScript 资产，并持续执行完整 Web/UI smoke。

### UI / Control / Audit 调用链与状态边界

```text
Browser
  -> Web UI
  -> session / CSRF / LAN ACL
  -> Web Gateway
  -> Unix socket
  -> proxy-agent-api-auth
  -> Control API v1
  -> validate
  -> revision store / audit
  -> reconcile / desired-observed
  -> runtime / health
  -> /api/v1/events -> audit-store read
```

UI 仅维护页面生命周期内的 `loadedConfig`、`baseRevision`、`pendingRevision` 与最后一次 validated candidate；Profile selector、structured form、event view 都是 presentation layer，不拥有权威状态。

远程 mutation 的审计边界位于实际部署的 `proxy-agent-api-auth` wrapper：`actor=web-ui` 的 mutation 在进入核心 Control API 前必须先成功写入 admission audit；审计 Store 不可用时返回非成功语义并阻断转发。现有本地 Control API 的 `safe_audit()` 不为 0.4.x 行为引入新的失败语义。

### 当前非目标

RBAC、多租户、SSO/OIDC、持久 session store、独立 ACL engine、Profile create/delete/write API、自动 failover/balancing、multi-egress selection、universal zero-downtime activation 仍未完成。后续切片继续复用这一安全边界与 Control API 权威状态。

### 0.5.2 当前集成基线

截至当前 `main`，0.5.2 的 Web/LAN 管理面代码已经完成认证、显式源地址 ACL、Profile discovery/selector、结构化 Backend/Egress 表单、异步表单同步、health/revision/event 只读视图以及 remote mutation audit admission boundary；相关 PR 的 CI 与 Upgrade Transaction Gate 均已通过后合并。

当前 `main` 的 `VERSION` 已为 `0.5.2`，并已通过 release-cut CI 与 Upgrade Transaction Gate。正式 Git Tag `v0.5.2`、容器 digest、GitHub Release 与 provenance 仍待 Tag publication 触发既有 release workflow 后完成，不能在此之前宣称 0.5.2 已正式发布。

## 发布治理变更

### v0.5.1 发布治理纠偏

首次 0.5.1 发布过程中，Tag 创建使用了一次性 bootstrap workflow。Tag 在 bootstrap commit 上创建，而随后分支进行了 workflow 清理，导致 Tag 内容与最终发布分支出现 provenance 偏差风险。

纠偏原则：

```text
Release Tag
   ==
Build Source
   ==
Container Source
   ==
Release Asset Provenance
```

后续 release workflow 必须显式 checkout `github.ref_name` 对应 Tag，并在日志中打印：tag、tag target commit、HEAD、tree、VERSION、image digest、workflow run id 与 Release URL。

### 发布日志要求

发布 workflow 必须至少输出：

- release context：event、ref、ref_name、run_id、repository。
- source identity：Tag target commit、HEAD、tree、commit metadata、clean working tree。
- version gate：Tag version 与 `VERSION` 的一致性。
- validation：shell syntax 等发布前校验结果。
- container provenance：image、version digest、latest digest。
- release provenance：source commit、source tree、image digest、workflow run URL、published timestamp。
- GitHub Release：创建结果、Release URL 与 assets。

这样可以从 CI 日志与 Release assets 反查一个发布物的实际来源，而不是只知道“workflow succeeded”。
