# 容器部署指南

`proxy-agent` 在容器中采用单进程前台模型，不在容器内运行 systemd。容器运行时负责进程监督、重启和资源限制，`proxy-ctl run` 负责 proxy-agent 自身的前台生命周期。

## 1. 构建

```bash
docker build -f Containerfile -t proxy-agent:0.2.0 .
```

镜像默认使用非 root 的 `proxy-agent` 服务账户运行。

## 2. 提供配置

生产部署必须提供真实配置，不能直接使用示例文件里的占位服务器：

```bash
docker run --rm \
  -p 127.0.0.1:1080:1080 \
  -v "$PWD/proxy-agent.conf:/etc/proxy-agent/proxy-agent.conf:ro" \
  proxy-agent:0.2.0
```

配置文件应保持最小权限；SSH backend 使用的私钥建议以只读方式挂载到服务用户可读取的位置。

## 3. 网络模型

容器不会自动向外发布代理端口。端口发布是部署者的明确选择。

常见方式：

### 容器向外提供代理

将 `SOCKS_BIND` 设为适合容器网络的监听地址，并通过 Docker/Kubernetes Service 或端口映射限制访问范围。不要在没有访问控制的情况下直接绑定 `0.0.0.0` 并暴露公网。

### 容器访问宿主机代理

推荐使用 Docker 的 host-gateway 能力显式建立宿主机解析，再在配置中引用宿主机代理地址。例如 Docker 环境可以使用：

```bash
docker run --add-host=host.docker.internal:host-gateway ...
```

随后在配置中使用 `host.docker.internal` 对应的服务端口。是否采用该方式取决于具体网络环境和安全边界。

### 多容器互联

为 proxy-agent 与业务容器加入同一个用户定义 Docker network，由容器名或服务名访问代理端口。这样通常比直接暴露宿主机端口更容易控制访问范围。

### Kubernetes

将 proxy-agent 作为独立 Deployment/Sidecar/专用服务均可，但应把两类健康信号分开理解：

- 容器 healthcheck / liveness 只代表本地控制平面与 backend 是否处于预期运行状态。
- `HEALTH_TARGETS` 配合 `HEALTH_NETWORK_REQUIRED=true` 才用于把上游网络可达性纳入工作负载 SLO。

不能因为公网目标短暂不可达，就直接判定本地 backend 已死亡。

## 4. 配置与权限

容器内运行账户不是 root，因此不要依赖 root 才能创建运行时目录、日志目录或修改系统服务。镜像已经准备：

- `/run/proxy-agent`
- `/var/log/proxy-agent`
- `/etc/proxy-agent`

生产配置覆盖 `/etc/proxy-agent/proxy-agent.conf`。

## 5. 升级

把镜像 tag 或不可变 digest 视为发布边界：

```text
新版本源码
  ↓
CI 构建与验证
  ↓
镜像 tag / digest
  ↓
部署新工作负载
  ↓
健康检查
  ↓
完成替换
```

回滚时优先使用上一版本已验证的 digest，而不是重新构建一个“看起来一样”的镜像。

容器内不要执行 `install.sh`、`upgrade.sh` 或 systemd 单元；这些属于宿主机部署路径。宿主机 rootless 使用 `install-user.sh`，系统级部署使用 `install.sh`。

## 6. 运维入口

容器内统一前台入口：

```bash
proxy-ctl run
```

人工诊断：

```bash
proxy-ctl status
proxy-ctl status --json=v2
proxy-ctl test
proxy-ctl diagnose
```

机器侧建议优先消费 `status --json` / `status --json=v2`，不要解析中文人类输出。
