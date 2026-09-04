# Local Control API v1

`proxy-agent` 0.4.x 提供本机 Control API v1，作为控制面的稳定后端入口。API 不直接暴露到远程网络，默认使用 Unix domain socket。

## Transport

Default socket:

```text
/run/proxy-agent/control.sock
```

默认权限为 `0600`。systemd 部署使用专用低权限服务账户运行 API service；远程 HTTP listener 不属于 Control API 合同。

## Profile selection

Named profiles can be selected per request with the `profile` query parameter on read endpoints or the `profile` field in mutating/runtime request bodies.

```text
GET /api/v1/status?profile=office
```

profile context resolves the configuration, runtime state directory, log directory and revision store as one context. Downstream commands must consume those resolved paths and must not append the profile name a second time.

## Read endpoints

```text
GET /api/v1/status
GET /api/v1/health
GET /api/v1/metrics
GET /api/v1/capabilities
GET /api/v1/config
GET /api/v1/events
GET /api/v1/revisions
GET /api/v1/revisions/{revision}
```

响应统一带有：

```json
{
  "api_version": "v1",
  "kind": "...",
  "data": {}
}
```

## Mutating endpoints

### Validate

```text
POST /api/v1/validate
```

请求：

```json
{
  "config": { "schema_version": 1 }
}
```

配置结构不满足当前 typed-config 基本合同时返回 `422 invalid_config`。

### Create revision

```text
POST /api/v1/revisions
```

支持 `if_match_revision` 乐观并发控制。成功创建后会写入 `revision.created` audit event。

### Apply

```text
POST /api/v1/apply
```

请求指定已存在 revision，可用 `if_match_revision` 防止并发覆盖。成功后设置 desired revision 并运行 reconciler。

激活失败返回：

```text
503 activation_failed
```

同时追加：

```text
 desired_state.activation_failed
```

这样调用方可以区分“请求错误”与“控制面已经接受但 runtime 激活失败”。

### Rollback

```text
POST /api/v1/rollback
```

rollback 不直接修改历史 revision，而是创建一个新的 revision，复制目标 revision 的 config，再把新的 revision 设为 desired state 并激活。

成功事件：`rollback.activated`；激活失败事件：`rollback.activation_failed`。

## Runtime operations

```text
POST /api/v1/runtime/start
POST /api/v1/runtime/stop
POST /api/v1/runtime/restart
POST /api/v1/runtime/test
POST /api/v1/runtime/diagnose
```

这些调用直接操作 runtime lifecycle，不创建或修改 revision。它们属于显式 runtime override，因此不会自动改变 `desired_revision`；desired/observed revision 仍表示控制面的声明与最近一次成功 reconciler activation。

## Revision model

revision 是不可变历史记录；desired state 单独保存当前期望 revision。

概念关系：

```text
revision history
      │
      ├── revision 1
      ├── revision 2
      └── revision 3  ← current head

      desired_revision ──→ revision 3

runtime observed_revision ──→ reconciler projection / activation
```

因此：

- `current_revision` 表示 revision history head。
- `desired_revision` 表示控制面要求 runtime 达到的 revision。
- `observed_revision` 表示 runtime 最近成功投影/激活的 revision。
- runtime 是否 ready 仍由 backend / adapter readiness 与 revision convergence 共同决定。

Apply 使用 `desired_revision` 与 reconciler 解耦，因此激活失败时允许出现 `desired_revision > observed_revision`；这是声明式控制面的正常中间状态，不会自动把 desired state 回滚成旧 revision。

## Optimistic concurrency

变更请求可以携带：

```json
{
  "if_match_revision": 12
}
```

若当前 head 已不是 `12`，API 返回：

```text
409 revision_conflict
```

Control API 不提供隐式的 last-write-wins。

## Audit

Audit 采用追加式 JSON Lines 保存。关键事件包括：

```text
revision.created
desired_state.activated
desired_state.activation_failed
rollback.activated
rollback.activation_failed
runtime.start
runtime.stop
runtime.restart
runtime.test
runtime.diagnose
```

事件 schema 位于：

```text
schemas/proxy-agent-audit-event.v1.json
```

revision schema 位于：

```text
schemas/proxy-agent-revision.v1.json
```

## Activation semantics

0.4.x 的 runtime 激活是受控 stop/start，不承诺 backend 级零停机 handover。API 的 `202` 表示本次 reconciler activation 已成功完成，而不是承诺永不中断。

backend 的 ownership contract 决定 stop 是否真正终止受管进程。对于 unmanaged backend，`stop` 可以保持 no-op；health readiness 仍依据 backend / adapter 的真实可用状态判断，而不是单纯依据“上一次 stop 被调用”。

真正的 zero-downtime handover 需要 backend-specific capability contract 单独定义，Control API 不假定所有 backend 都支持。

## Security boundary

0.4.x Control API 仅用于本机控制面：

- Unix socket only by default。
- Socket mode `0600`。
- systemd 使用专用低权限服务账户。
- `allow_public_listener=true` 不是 API 的默认远程暴露开关；当前 API 不提供未经认证的远程管理入口。

后续 Web Control Plane 应继续把本 API 当作后端合同，而不是重复实现 revision / audit / reconcile 逻辑。
