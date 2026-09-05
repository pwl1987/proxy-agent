# 0.5.2 Web Session Security Boundary

本阶段建立 Web Gateway 的第二层安全边界：在现有 admin token 基础上增加短期会话、CSRF 防护与登录失败限流，并把写操作安全地委托给 Control API v1。

## 责任边界

```text
Browser
  -> Web Gateway session/auth/CSRF/rate-limit
  -> Unix socket
  -> Control API v1
  -> revision / audit / desired-observed / reconcile
```

Web Gateway 不直接读写 revision、audit、runtime 文件，也不实现第二套生命周期或 reconciliation。

## 会话

- admin token file 仍是 bootstrap credential。
- 登录成功后生成不可预测的随机 session id 与 CSRF token。
- session 在进程内存中保存，默认 30 分钟空闲续期，最多 256 个 session。
- Gateway 重启后 session 失效，避免把 Web session 引入持久状态模型。
- cookie 使用 `HttpOnly`、`SameSite=Strict`；TLS listener 额外设置 `Secure`。

## CSRF

所有 Web 的 POST 控制操作必须同时满足：

1. 有效 session cookie。
2. `X-CSRF-Token` 与 session token 一致。
3. Origin/Referer 与当前 Gateway origin 一致（没有浏览器提供的 Origin/Referer 时不额外阻断非浏览器客户端）。

这样 cookie 不会成为绕过写操作认证的隐式凭证。

## 登录限流

按对端 IP 维护滑动窗口：每 60 秒最多 5 次失败登录。成功登录不会消耗失败配额。超限返回 HTTP 429，不把内部 token 状态泄漏给客户端。

## 写操作

Gateway 允许的 POST 路由只映射到既有 Control API v1：

- `/api/v1/validate`
- `/api/v1/revisions`
- `/api/v1/apply`
- `/api/v1/rollback`
- `/api/v1/runtime/start`
- `/api/v1/runtime/stop`
- `/api/v1/runtime/restart`
- `/api/v1/runtime/test`
- `/api/v1/runtime/diagnose`

Gateway 只做认证、CSRF、请求大小和协议边界，不复制 Control API 的 revision、audit、validation、activation 或 reconcile 逻辑。

## 本阶段非目标

本阶段不引入持久 session store、RBAC、多用户目录、独立 ACL engine 或 UI framework。profile/backend/egress 管理 UI 与 validate -> diff -> apply 页面继续建立在这个安全边界之上。