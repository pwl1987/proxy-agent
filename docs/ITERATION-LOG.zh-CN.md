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

## 0.5.2 — Web Gateway Foundation（已进入 main，但在 0.5.1 发布收口完成前冻结）

> 0.5.2 代码已经进入 `main`，但它不是 `v0.5.1` 的组成部分。正式开发推进必须在 0.5.1 provenance 与发布治理收口后继续。

### 已进入代码的能力

- `bin/proxy-agent-web`。
- loopback 默认监听。
- Bearer token。
- 非 loopback 场景要求 TLS。
- 通过 Unix socket 只读代理 Control API v1。
- mutating methods 明确拒绝。
- `no-store` 响应策略。
- Web gateway smoke 与相关功能门禁。

### 下一阶段需要继续记录

0.5.2 后续迭代必须按“能力 -> 调用链 -> 状态影响 -> 安全边界 -> 兼容性 -> 测试 -> 发布物”逐项登记，不再只以 PR 标题作为功能日志。

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
