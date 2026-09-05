# 0.5.2 Web Management Service

## 本次切片

将已经完成的 Web Gateway / Web UI 从“仓库代码可运行”推进到“系统级安装可运行”的部署闭环。

### 真实部署链

```text
install.sh
  -> /opt/proxy-agent/bin/proxy-agent-web-ui
  -> /opt/proxy-agent/web/index.html
  -> proxy-agent-web.service
  -> proxy-agent-api.service
  -> /run/proxy-agent/control.sock
  -> Control API v1
```

### 安全默认值

- Web service 默认监听 `127.0.0.1:8443`。
- `/etc/proxy-agent/web-admin-token` 不存在时，systemd 通过 `ConditionPathExists` 不启动 Web service。
- Web service 依赖 `proxy-agent-api.service`，不直接接触 backend lifecycle、revision store 或 audit store。
- `web.env` 可以覆盖 listener、control socket 与 TLS 证书/私钥路径；非 loopback listener 仍由 Web Gateway 强制要求 TLS。
- 安装器默认不 enable Web service，避免安装时在未准备 admin credential 的情况下自动开放管理面。

### 安装器变更

`install.sh` 现在：

- 同时安装 `web/` 静态页面资源。
- 创建 `proxy-agent-web-ui` CLI symlink。
- 安装 `proxy-agent-web.service`。
- 安装 `web.env.example` 与默认 `/etc/proxy-agent/web.env`。
- 输出 Web bootstrap 与启动说明。

### 状态边界

Web service 只是 User Surface / Deployment 层的入口；现有 Control API v1 仍拥有：

- typed config validation
- revision / optimistic concurrency
- audit event
- desired / observed state
- reconcile / activation
- runtime lifecycle

因此本切片没有新增 Web-side state machine。

### 当前非目标

rootless user-systemd 的独立 Web service、LAN ACL、证书自动签发、RBAC、多用户身份以及公网安全策略仍属于后续 0.5.2 slice。