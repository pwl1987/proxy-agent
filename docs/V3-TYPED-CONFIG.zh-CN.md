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

Secret 不进入普通配置字段。后续使用 secret reference。

## 后端选项

`backend.options` 保持 backend-specific 扩展空间，但具体字段必须由 backend contract 定义。Control API 不应把 backend 名称硬编码成 UI 逻辑。

下一步会把现有：

- `ssh-socks`
- `local-endpoint`
- `sing-box`
- `mihomo`
- `http-connect`

逐一映射到 typed backend options，并增加 capability metadata。

## 兼容策略

现有 `.conf` 继续支持：

```text
legacy .conf
    ↓
parse
    ↓
Typed Config
    ↓
统一 validation
```

不允许新的业务功能继续直接读取并扩展 Shell 全局变量；新增能力必须首先进入 typed model。

## 0.3.x 第一阶段 Gate

1. schema 文件可被标准 JSON Schema validator 加载。
2. 至少一份 canonical 示例配置通过 schema validation。
3. legacy `.conf` 到 typed model 的字段映射完成。
4. typed model 能生成稳定 diff。
5. Control API 后续直接消费 typed model，而不是重新解析 Shell 配置。

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
