# Host / Container 网络部署指南

`proxy-agent` 的网络边界应明确分成三层：代理 backend、本机控制平面、外部业务流量。部署时不要把“监听成功”和“公网可达”混为一件事。

## 1. 宿主机 systemd

系统级部署默认面向本机服务：

```bash
sudo ./install.sh
sudo proxy-ctl validate
sudo systemctl enable --now proxy-agent.service
```

默认 SOCKS 监听使用 loopback。只有明确需要局域网客户端访问时，才应扩大监听范围，并同时配置防火墙、ACL 或反向代理层。

## 2. rootless

用户态部署：

```bash
./install-user.sh
proxy-ctl validate
systemctl --user enable --now proxy-agent.service
```

rootless 服务的数据路径使用 XDG / 用户 runtime 目录，不需要写 `/etc`、`/run` 系统目录。

## 3. Docker Bridge

最常见的容器方式是自定义 Docker network：

```bash
docker network create proxy-net
```

proxy-agent 与业务容器加入同一个网络后，业务容器可以通过服务名访问代理监听端口。建议只把代理端口暴露在该网络中，不必发布到宿主机公网接口。

## 4. 容器访问宿主机代理

需要访问宿主机上的代理服务时，可以显式增加 host-gateway 映射：

```bash
docker run \
  --add-host=host.docker.internal:host-gateway \
  ...
```

然后使用 `host.docker.internal` 作为目标地址。该方式的实际行为取决于 Docker 运行环境；不能假设所有容器运行时都自动提供同名解析。

## 5. Kubernetes

可以将 proxy-agent 作为：

- 独立 Deployment + Service；
- 应用 Pod 内 Sidecar；
- 专门的代理工作负载。

无论哪种模式，都建议把健康信号拆成：

```text
本地进程 / backend liveness
        ↓
代理服务可用性
        ↓
实际上游网络 health
```

例如业务 SLA 要求“必须能访问 GitHub / PyPI / npm”，才启用：

```bash
HEALTH_NETWORK_REQUIRED=true
```

否则短暂公网故障不应触发本地 backend 重启。

## 6. 监听地址安全边界

推荐顺序：

```text
127.0.0.1
   ↓
Docker / Kubernetes 私有网络
   ↓
局域网受控地址
   ↓
公网监听（必须明确授权）
```

尤其是 SOCKS5，一旦错误绑定 `0.0.0.0`，可能直接变成开放代理。生产环境应将监听范围、端口映射、防火墙和访问控制作为一个整体设计。

## 7. HTTP / SOCKS 能力

Backend 能力决定 `proxy-ctl env` 应如何生成环境变量：

- SOCKS5 backend：提供 `ALL_PROXY`。
- HTTP-native backend：直接提供 HTTP/HTTPS proxy 环境变量。
- Privoxy adapter：把 SOCKS5 转成 HTTP 后再提供 HTTP/HTTPS proxy。

不要对已经原生支持 HTTP 的 backend 再强制套用 Privoxy。

## 8. 故障定位

建议按以下顺序检查：

```bash
proxy-ctl status --json=v2
proxy-ctl capabilities
proxy-ctl route github.com
proxy-ctl test
proxy-ctl diagnose
proxy-ctl health-history
```

`status` / `liveness` 主要回答“代理控制平面和 backend 是否正常”；`test` / health history 才用于回答“实际业务网络是否正常”。
