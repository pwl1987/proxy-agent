# V3 Typed Config 设计与迁移约束

## 目标

0.3.x 开始引入 canonical typed configuration。现有 Shell `.conf` 不在这一阶段立即删除，而作为兼容输入；新的 Control API、Web UI、TUI 和 Agent 集成统一面向 typed model。

## 数据边界

```text
TOML / legacy .conf / API JSON
          ↓
     Typed Config Model
          ↓
      Schema Validate
          ↓
      Revision / Diff
          ↓
     Desired State
          ↓
       Reconciler
          ↓
     Runtime / Backend
```

## Schema 规则

机器 schema 为 JSON Schema Draft 2020-12；schema 自身的版本字段为 `schema_version`，与 `proxy-agent` 发布版本独立。

V1 typed model 固定以下一级对象：

- `backend`
- `listeners`
- `routing`
- `health`
- `integrations`
- `security`

`routing.rules` 保留旧版路由语义，但在 typed model 中明确为：

```text
priority + action + matcher + pattern
```

其中 `action` 使用小写 canonical 值 `direct` / `proxy`，`matcher` 使用 `exact` / `suffix` / `wildcard` / `cidr`。

Secret 不进入普通配置字段。后续使用 secret reference；迁移工具也不会读取或复制私钥内容。

## 后端能力契约

后端名称、托管属性、能力以及 typed options 已建立独立的机器契约：

- `schemas/proxy-agent-backends.json`：实际 capability manifest。
- `schemas/proxy-agent-backends.schema.json`：manifest 的 JSON Schema。

当前五类 backend 均有明确 metadata：

```text
ssh-socks       managed   socks5 + dynamic_dns + stream_proxy
local-endpoint  unmanaged stream_proxy + URL-derived capability
sing-box        managed   socks5 + stream_proxy
mihomo          managed   socks5 + stream_proxy
http-connect    unmanaged http_native + stream_proxy
```

`local-endpoint` 的 `socks5` / `http_native` 能力由 `LOCAL_PROXY_URL` scheme 推导，避免 UI 或 Control API 猜测 backend 行为。

`backend.options` 保持 backend-specific 扩展空间，但具体字段必须由 backend contract 定义。Control API 不应把 backend 名称硬编码成 UI 逻辑。

## Legacy `.conf` 迁移

0.3.x 已提供只读迁移出口：

```text
proxy-ctl config export-typed
```

执行流程固定为：

```text
legacy .conf
    ↓
现有 config_validate
    ↓
受控字段映射
    ↓
canonical typed JSON
```

迁移器 `lib/legacy-typed-export.py` 只读取显式 allow-list 环境字段，不执行 Shell 内容，也不读取 secret 文件。旧版 `REMOTE_SSH_KEY` 被表达为 `remote_ssh_key_ref`，不会把私钥内容写入 JSON。

旧版路由规则会被转换为稳定排序的 typed objects；因此相同 legacy 配置产生确定性的 JSON，有利于后续 Revision / Diff。

公共监听是一个有意的安全边界：迁移不会把 `0.0.0.0` / `::` 之类的公开监听隐式转换成 typed 配置。需要公开暴露时，必须在 typed deployment policy 中做显式决定。

## 兼容策略

现有 `.conf` 继续支持，但新增业务能力不得再直接扩展 Shell 全局变量。新增能力必须首先进入 typed model，并补齐 schema、backend metadata 与 smoke contract。

## 0.3.x 当前 Gate

1. canonical typed schema 已确定，并有示例与结构 smoke。
2. 五类现有 backend 已完成 legacy → typed options 映射。
3. route rule 的 priority/action/matcher/pattern 语义已固化。
4. backend capability manifest 已建立，并与现有 backend Shell capability 实现做 CI 对照。
5. `proxy-ctl config export-typed` 已作为 CLI 控制面入口，并由 CI smoke 验证机器可解析 stdout。
6. Revision / Diff / Control API 将直接消费 typed model，而不是重新解析 Shell 配置。

当前 CI smoke 重点验证结构、字段边界、安全拒绝条件和 capability drift；尚未把第三方 JSON Schema validator 作为运行时依赖强行带入项目，因此“schema 可由标准 validator 加载”仍属于后续增强 Gate，而不是被当前 smoke 伪装成已完成的事项。

## Agent 关系

AI Agent 集成属于 Control API 上层能力：

```text
Agent
  ↓
Agent Environment Contract
  ↓
Control API
  ↓
Typed Config / Desired State
  ↓
proxy runtime
```

因此 `agent install` 不应直接修改任意系统文件；它最终应提交一个受 schema、revision、audit 和 health gate 管理的环境变更。
