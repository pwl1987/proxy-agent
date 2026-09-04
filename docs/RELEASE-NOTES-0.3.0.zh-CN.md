# proxy-agent v0.3.0

## 发布定位

`v0.3.0` 是 proxy-agent 从 legacy 配置与直接运行时控制，向 **Typed Config + Control Plane + Desired/Observed State + Reconciler** 架构收口的版本。

## 核心能力

### 1. Typed Configuration Contract

- 建立 canonical Typed Config v1 数据模型与 JSON Schema Draft 2020-12。
- 建立 legacy `.conf` → Typed Config 的迁移边界。
- 建立 Typed Config → legacy runtime variables 的兼容投影，保证现有 backend/runtime 仍可运行。
- 新的控制面能力以 Typed Config 作为配置数据边界，而不是继续扩张 Shell 全局变量。

### 2. Control Plane v1

- 提供 Local Control API v1。
- 引入 revision、desired state、observed state 的生命周期模型。
- 支持配置 apply、rollback 与 optimistic concurrency。
- 配置变更进入 revision store，再进入 desired state，由 reconciler 负责运行时收敛。

### 3. Reconciler / Runtime Ownership

- reconciler 校验 desired revision 与配置一致性。
- Typed Config 投影为 runtime candidate 后执行原子切换。
- runtime state 持续记录 backend、adapter、health、lifecycle 与 observed revision。
- 激活失败会进入 audit，避免控制面显示成功而运行时实际失败。

### 4. Backend Capability Contract

- backend 能力以显式 capability contract 暴露。
- Control Plane / CLI 根据 capability 决定 endpoint、代理协议及相关环境变量，而不是硬编码假设单一 backend。

### 5. Agent Network Environment Contract

新增 Agent 网络环境接口：

- `proxy-ctl agent install`
- `proxy-ctl agent status`
- `proxy-ctl agent env`

`agent env` 提供稳定的 JSON v1 contract，包括：

- `schema_version`
- `profile`
- `http_proxy`
- `https_proxy`
- `all_proxy`
- `no_proxy`

`agent status --json` 同时报告 backend、adapter、health 以及 Git / Docker / pip / npm integration 状态。

### 6. 运维与安全

- profile 隔离与安全 profile 名称校验。
- 配置文件安全权限检查。
- rootless / systemd / container 场景持续保留。
- `proxy-ctl exec` 在子进程边界重新构造代理环境，并清理继承的代理变量。
- audit store 使用追加式 JSONL 与锁保护。

## 兼容性

- legacy `.conf` 仍作为输入兼容层保留。
- 现有 backend、adapter、integration 运行路径继续通过 legacy runtime projection 工作。
- v0.3.0 不要求一次性迁移所有已有部署到 Typed Config 原生存储。

## 已验证发布门禁

v0.3.0 tag 指向冻结提交 `06f9f60a2e034e21aa1a8bf61a404b6bebd44884`。

发布前后的 CI / Release workflow 均成功完成；Release workflow 同时完成版本一致性校验、Shell 语法检查、Container 构建、GHCR 推送及 GitHub Release 创建。

## 明确延期到后续版本

以下事项不属于 v0.3.0 的发布阻塞项：

- Agent connectivity probe / 网络连通性探测 contract。
- 更丰富的 health / readiness / liveness 语义。
- Typed Config 的进一步原生化存储与迁移编排。
- backend capability 的进一步扩展。
- 0.4.x 的架构演进与新功能。

v0.3.x 在此冻结，不再继续叠加新的业务能力；后续工作进入 0.4.x。