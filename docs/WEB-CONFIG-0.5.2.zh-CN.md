# 0.5.2 Web Configuration Management

## 本次业务切片

本切片在既有 Web Gateway session / CSRF 安全边界之上，落地最小可用的配置管理工作流：

```text
Web UI
  -> GET status/config/revisions/health
  -> 本地生成 candidate diff
  -> POST /api/v1/validate
  -> POST /api/v1/revisions + if_match_revision
  -> POST /api/v1/apply + if_match_revision
  -> Control API v1
  -> Revision / Audit / Reconciler / Runtime
```

## UI 边界

- 页面通过 `bin/proxy-agent-web-ui` 暴露。
- UI 本身不持久化配置、revision、session 或 secret。
- session 继续由 Gateway 进程内存管理；UI 只携带 HttpOnly session cookie 与 CSRF token。
- 页面只调用现有 Control API v1，不直接访问 revision store、audit store、runtime 文件或 backend 进程。
- candidate diff 在浏览器内计算，避免为了 UI diff 增加第二套后端状态模型。

## 当前支持的业务操作

- Profile 参数输入（空值表示默认 profile）。
- 查看 runtime、health、current/desired revision 和 recent revisions。
- 编辑 typed JSON 配置。
- Validation：调用 Control API `/api/v1/validate`。
- Diff：当前编辑内容与加载时 typed configuration 的结构化字段 diff。
- Revision：使用 `if_match_revision` 创建 revision，发生并发修改返回 409。
- Apply：仅允许已创建的 pending revision，并以 revision 本身作为 optimistic-concurrency 边界。
- Logout：清理当前 session。

## 状态与并发

UI 不维护 desired/observed 状态，只保存当前页面的短生命周期变量：

```text
loadedConfig       页面加载时的 candidate baseline
baseRevision       创建 Revision 时的 expected head
pendingRevision    已成功创建、等待 Apply 的 revision
validatedConfigText 最后一次通过 Validation 的 candidate
```

真正权威状态仍在 Control API 的 revision store / reconcile-state / runtime 层。

## 安全边界

- admin token 只用于建立 session。
- session cookie 为 HttpOnly、SameSite=Strict；TLS listener 下增加 Secure。
- 所有 mutation 继续要求 session + CSRF + same-origin。
- Gateway 的 1 MiB request body limit 仍适用。
- UI 没有第三方 CDN、远程脚本或外部字体依赖。

## 容器与验证

`Containerfile` 现在显式打包 `web/`，因此 UI 与 Gateway 代码一同进入容器文件系统。

CI 增加：

- `bin/proxy-agent-web-ui` Python syntax check。
- `tests/web-ui-smoke.sh`，验证 UI 页面、关键业务路由、no-store、session 登录和 Control API 代理边界。
- 原有 Web Gateway、Functional、Path Health、Revision/Audit/Reconciler、Upgrade Transaction Gate 继续作为回归门禁。

## 后续切片

当前仍不包含 RBAC、持久 session、多租户、独立 ACL engine，以及更丰富的 Profile/Backend/Egress 表单组件。这些功能继续建立在本切片形成的安全 session 与 Control API 权威边界之上。
