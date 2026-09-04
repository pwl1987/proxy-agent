# proxy-agent 下一阶段架构设计

本文冻结下一阶段架构方向，避免继续在 Shell CLI 上无限堆功能。0.2.0 作为 Linux reference implementation 正式收口；后续功能通过控制协议逐步演进。

## 一、结论

当前 `proxy-agent` 的 Linux Shell 控制平面已经适合作为 **0.2.x 稳定基线**：Backend、Adapter、Route、Health、Profile、systemd、rootless、container、TUI、CI/CD 均已有正式边界。

下一阶段不再以“增加更多 CLI 子命令”为主，而是逐步把控制平面提升为：

```text
                    ┌─────────────────────────────┐
                    │      proxy-agent control     │
                    │          daemon/API          │
                    ├──────────────┬──────────────┤
                    │ desired      │ observed     │
                    │ config/state │ runtime/state │
                    ├──────────────┴──────────────┤
                    │ reconciler / lifecycle       │
                    │ health / routing / audit     │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                  CLI            TUI            Web UI
                    │              │              │
                    └──────────────┴──────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │ backend / adapter / runtime │
                    └─────────────────────────────┘
```

核心原则：**一个控制平面、多个操作入口、多个运行时、多个平台。**

## 二、为什么现在不直接重写

当前 Shell 实现已经把真正重要的领域模型暴露出来：

- backend lifecycle
- capabilities
- ownership
- route policy
- profile
- health semantics
- desired/active runtime state
- systemd/rootless/container lifecycle

这些边界应先冻结，再决定是否迁移实现语言。

直接把现有 Shell 一次性重写成 Go/Rust，会同时改变行为、安装方式、配置、故障语义和 CI，回归面过大。

因此采用“**先协议化，再替换实现**”策略：

1. 0.2.x：维护 Shell reference implementation。
2. 0.3.x：定义本地 control API 与 typed config model。
3. 0.4.x：CLI/TUI 优先切到 API；Shell 保留兼容入口。
4. 0.5.x 以后：根据跨平台需求决定是否把 daemon 核心迁移到 Go/Rust。

## 三、Web UI 的正确位置

Web UI 建议增加，但不是简单把 `proxy-agent.conf` 做成网页文本编辑器。

正确操作流应为：

```text
查看当前状态
   ↓
创建配置草稿
   ↓
Schema 校验
   ↓
显示 Diff
   ↓
执行 Apply
   ↓
启动/重载 Backend
   ↓
Liveness Gate
   ↓
可选 Network Health Gate
   ↓
记录 revision + audit event
```

Web UI 第一版只负责：

- Profile 管理
- Backend/Adapter 选择
- endpoint 与监听配置
- Route 规则编辑
- Health 目标编辑
- 查看状态/健康/日志
- Apply、Restart、Rollback
- 导出配置

不要在第一版做：

- 任意 Shell 执行
- 直接编辑私钥
- 默认远程公网管理
- 多租户
- 复杂 RBAC 平台化

## 四、配置模型必须从“可执行 Shell”升级为“类型化数据”

当前配置通过 Shell `source` 加载，已有 ownership/mode 保护，但其本质仍然是可执行文本。

下一阶段应定义 canonical typed configuration：

```text
Config Schema
   ├─ metadata
   ├─ backend
   ├─ adapter
   ├─ listeners
   ├─ routes
   ├─ integrations
   ├─ health
   └─ security
```

建议：

- JSON Schema：作为校验与 Web API 的机器模型。
- TOML：作为主要人工配置格式。
- 现有 `.conf`：作为过渡兼容格式。

迁移期间，CLI 可以将旧 `.conf` 解析为内部 typed model，再统一执行 validation 和 apply。

## 五、从命令式控制转向 Desired / Observed State

当前：

```text
proxy-ctl start
proxy-ctl stop
proxy-ctl restart
```

下一阶段：

```text
Desired State
    ↓
Reconciler
    ↓
Observed State
    ↓
Health / Failure
    ↓
再协调
```

例如 Backend 异常退出：

```text
desired=running
observed=dead
     ↓
bounded recovery
     ↓
observed=ready
```

这样 CLI、TUI、Web UI、systemd、container 就不再各自实现一套生命周期逻辑。

## 六、配置变更必须有 revision

所有 Apply/Upgrade/Rollback 都应生成：

```text
revision
previous_revision
timestamp
actor
change_summary
validation_result
health_result
```

Web UI 不应直接覆盖生产配置，而应提交一个 revision。

这样可以实现：

```text
v12 → v13 → v14
          ↓
        rollback
          ↓
         v13
```

同时避免两个客户端同时写配置产生 lost update。

## 七、远程 Web 管理的安全边界

默认策略必须是：

```text
默认：只监听 localhost / Unix socket

远程管理：显式开启
         ↓
    TLS / 身份认证
         ↓
      Audit Log
```

尤其禁止把“Web 配置页面”直接绑定 `0.0.0.0` 并且无认证。

SSH、VPN、Tailscale、反向代理等都可以作为远程管理的安全通道，但控制面本身仍然要有独立认证边界。

私钥、代理认证信息等 Secret：

- 页面默认只显示存在/已配置，不回显原文。
- Apply 时支持 secret reference，而不是把私钥作为普通配置字段保存。
- 后续实现统一 secret provider 接口：file / env / OS keyring / platform credential store。

## 八、跨系统路线

跨系统不等于把所有 Shell 脚本复制到 Windows/macOS。

推荐把系统相关层收敛成：

```text
                Control API
                     │
        ┌────────────┼────────────┐
        │            │            │
      Linux        macOS       Windows
      systemd      launchd      Windows Service
      XDG/root     launchd      Service profile
      container    container    container/WSL
```

第一优先级：Linux。

第二优先级：macOS + Windows 的 client/controller。

第三阶段再决定是否提供原生 daemon。

如果确实需要单文件跨平台 daemon，届时优先评估 Go/Rust；当前不为了“跨平台”而复制三套生命周期实现。

## 九、CLI/TUI 的升级方向

当前 TUI 是 CLI 的薄壳，这个边界正确，但随着 Web/API 出现，应变成：

```text
CLI ─┐
TUI ─┼─→ local control API ─→ daemon
Web ─┘
```

同时保留：

```text
proxy-ctl validate
proxy-ctl route ...
proxy-ctl status --json=v1
proxy-ctl status --json=v2
```

机器接口继续向后兼容。

建议增加：

```text
proxy-ctl exec <command...>
```

让用户可以直接在代理环境中执行命令，减少手工 `eval "$(proxy-ctl env)"` 带来的操作复杂度。

## 十、AI Agent 安装与运行环境接入

`proxy-agent` 应提供面向 AI Coding Agent / 自动化 Agent 的统一安装与环境接入层，但不把不同 Agent 的逻辑散落成独立代理实现。

目标架构：

```text
                 proxy-agent Control Plane
                           │
                  Agent Environment Contract
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   Claude Code           Codex         Gemini / OpenClaw
        │                  │                  │
        └──────────────统一代理环境─────────────┘
```

建议在 0.3.x 提供：

```bash
proxy-ctl agent install
proxy-ctl agent status
proxy-ctl agent env
proxy-ctl agent env --json
proxy-ctl agent env --shell bash
proxy-ctl exec <command...>
```

其中：

- `agent install`：安装/初始化 proxy-agent，并创建 Agent 专用 profile；不应复制另一套控制逻辑。
- `agent env`：生成标准 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY` 环境。
- `agent status`：检查 proxy-agent、endpoint、路由及 Agent 所需的 Git/包管理器/容器 registry 等连通性。
- `proxy-ctl exec`：在代理环境中直接执行 Agent 或命令，减少手工 `eval`。
- `--json`：供 Agent、脚本和编排系统稳定消费；人类 CLI/TUI 仍以中文为主。

Agent 安装器只负责安装与初始化；**Control Plane 负责配置、生命周期、健康和回收**。禁止把安装脚本演变成第二个控制系统。

第一阶段默认不负责管理第三方 Agent 的账号、模型 API Key 或私有凭据；这些保持由 Agent 本身或外部 Secret Provider 管理。代理侧仅提供必要的环境与 connectivity contract。

推荐完整体验：

```text
proxy-ctl agent install
        ↓
检测平台 / 用户 / rootless
        ↓
安装或升级 proxy-agent
        ↓
创建 agent profile
        ↓
配置代理环境
        ↓
Git / package registry / container registry probes
        ↓
Agent Environment = READY
```

这一层的目标不是“支持某一个 AI Agent”，而是建立一个稳定的 **Agent Network Environment Contract**，后续各类 Agent 只做轻量适配。

## 十一、健康与可观测性

现有 health-history 已足够支撑单机运维，但下一阶段应逐步增加：

- probe 类型
- 目标
- 延迟
- DNS/连接/TLS/HTTP 错误分类
- 连续失败次数
- 最近一次恢复
- backend restart 次数
- 当前 generation/revision

并提供：

```text
/health
/status
/metrics
/events
```

其中 `/metrics` 可采用 Prometheus 文本格式，JSON API 保持给 Web/UI 使用。

## 十二、Backend contract 继续演进

现有 capability 已经是正确方向，但下一版应正式版本化：

```text
contract_version
capabilities[]
transport
lifecycle
management
```

例如：

```json
{
  "contract_version": 1,
  "capabilities": ["socks5", "stream_proxy"],
  "managed": true
}
```

这样 Web UI 可以根据 capability 自动决定显示哪些配置项，而不用写死 backend 名称。

## 十三、升级系统的最终形态

当前升级已具备配置保留和验证后恢复能力，但长期目标仍应改为版本目录 + 原子切换：

```text
/opt/proxy-agent/releases/0.2.0
/opt/proxy-agent/releases/0.3.0
/opt/proxy-agent/current -> 0.3.0
```

升级：

```text
install 0.3.0
    ↓
validate
    ↓
health gate
    ↓
switch current atomically
    ↓
restart/reconcile
```

失败：

```text
current -> 0.2.0
```

这比覆盖原目录更适合真正的生产回滚。

## 十四、推荐版本路线

### 0.2.0 — 已收口

目标：稳定 Linux reference implementation。

已完成：

- CI 全绿
- container runtime gate
- backend compatibility baseline
- release workflow
- rollback policy
- 中文 CLI/TUI/运维文档
- main 合并基线

### 0.3.x

目标：控制面协议化。

增加：

- typed config schema
- local API
- revision/audit
- `/status` `/health` `/metrics`
- `proxy-ctl exec`
- Agent Environment Contract
- `proxy-ctl agent install/status/env`
- TUI API client

### 0.4.x

目标：Web 控制面。

增加：

- Web UI
- Draft → Validate → Diff → Apply
- Rollback
- capability-driven forms
- local-only default

### 0.5.x

目标：跨平台。

增加：

- macOS runtime adapter
- Windows runtime adapter
- platform-specific installers
- cross-platform CI

### 1.0

目标：稳定 control-plane API。

此时再决定核心 daemon 是否从 Shell 迁移到 Go/Rust。

## 十五、Git 分支策略

不建议重新建立长期 `develop` 分支。

推荐：

```text
main
 │
 ├─ feat/*
 ├─ fix/*
 └─ release/*
```

规则：

- `main` 永远可发布。
- feature branch 短命。
- PR 合并后删除 branch。
- 发布使用 tag，不建立长期 release branch。
- 重要版本通过 release gate 决定，而不是依赖分支长期漂移。

## 十六、0.2.0 收口状态

PR #15 已合并至 `main`。0.2.0 的工程基线已经冻结，后续不再向 `release-engineering` 继续追加功能。

发布闭环：

```text
0.2.0 main baseline
      ↓
CI green
      ↓
merge #15
      ↓
tag v0.2.0
      ↓
GHCR image + digest
      ↓
GitHub Release
```

下一阶段只从 `main` 创建短命 feature branch，优先实现 V3 Control API 与 Typed Config，并以 Agent Environment Contract 作为其首个面向自动化客户端的正式集成协议。
