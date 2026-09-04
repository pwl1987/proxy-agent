# proxy-agent

通用 Linux Proxy Agent：统一管理代理后端、分流策略、环境变量、应用适配与健康检查。

> 从 `devops-scripts/proxy-agent` 独立演进。新项目不再绑定具体服务器、IP、目录或单一出口。

## 目标

- **Backend 可插拔**：当前支持 SSH → SOCKS5，后续可扩展 HTTP CONNECT、sing-box、mihomo 等。
- **Adapter 可插拔**：当前提供可选 Privoxy HTTP adapter。
- **Routing 与 Backend 解耦**：直连 / 代理由策略决定，而不是写死在部署脚本里。
- **安全默认值**：本地监听默认 `127.0.0.1`，SSH host key 校验默认开启。
- **应用适配**：Git、Docker、pip、npm 通过独立 integration 模块生成配置，不让主控制器继续膨胀。
- **可诊断**：`status`、`test`、`diagnose`、`route`、`doctor` 提供明确故障定位信息。
- **VM / container**：核心逻辑尽量无状态，systemd、Docker 等作为运行时适配层。

## 快速开始

```bash
sudo ./install.sh
sudo editor /etc/proxy-agent/proxy-agent.conf
sudo proxy-ctl doctor
sudo proxy-ctl start
sudo proxy-ctl status
sudo proxy-ctl test
```

当前 shell 使用代理：

```bash
eval "$(proxy-ctl env)"
```

关闭：

```bash
eval "$(proxy-ctl env --off)"
```

## 配置模型

配置文件描述意图，不包含项目路径或特定机器假设：

```bash
BACKEND="ssh-socks"
REMOTE_HOST="your-ssh-host"
REMOTE_USER="proxy"
REMOTE_PORT="22"
REMOTE_SSH_KEY="~/.ssh/id_ed25519"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"

# Optional HTTP adapter
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
PRIVOXY_CONFIG="/etc/proxy-agent/privoxy.conf"

DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
DIRECT_DOMAINS="localhost,.local,.cn"
NO_PROXY_EXTRA=""

HEALTH_TARGETS="https://github.com,https://pypi.org,https://registry.npmjs.org"
HEALTH_TIMEOUT="10"
HEALTH_RETRIES="2"
HEALTH_BACKOFF="2"
HEALTH_AUTO_RECOVER="true"
```

## CLI

```text
proxy-ctl start
proxy-ctl stop
proxy-ctl restart
proxy-ctl status
proxy-ctl test
proxy-ctl diagnose
proxy-ctl doctor
proxy-ctl route <host-or-ip>
proxy-ctl env [--off]
proxy-ctl integration <git|docker|pip|npm|all>
```

`route` 目前解释 domain / IPv4 CIDR 策略；它是策略诊断命令，不会修改系统路由表。

## Application integrations

Integration 命令只生成配置/命令，不默认修改用户系统配置：

```bash
proxy-ctl integration git
proxy-ctl integration docker
proxy-ctl integration pip
proxy-ctl integration npm
proxy-ctl integration all
```

Git 支持 SOCKS5；Docker、pip、npm 当前要求 `HTTP_ENABLED=true`，因为这些客户端的通用配置路径不能假定原生 SOCKS 支持。启用 HTTP adapter 后，再使用相应 integration 输出的命令。

## HTTP adapter

默认只提供 SOCKS5，避免额外暴露面和额外 daemon。设置 `HTTP_ENABLED=true` 后，agent 会生成并管理一个本地 Privoxy 实例，并将 HTTP 请求转发到本地 SOCKS5。

## Health / Recovery

安装 systemd 后可启用：

```bash
sudo systemctl enable --now proxy-agent-health.timer
```

健康检查会按配置执行重试；失败后可自动执行一次 `proxy-ctl restart` 并再次验证。`PA_STATE_DIR` 下保存最近的 healthy / unhealthy / recovered 时间戳。

## 安装器

默认安装到 `/opt/proxy-agent`；也支持通过环境变量覆盖：

```bash
sudo PREFIX=/srv/proxy-agent ./install.sh
```

systemd health unit 会同步使用自定义 `PREFIX`。

## 架构

```text
                    +----------------------+
                    |      proxy-ctl       |
                    +----------+-----------+
                               |
          +--------------------+---------------------+
          |                    |                     |
       Config               Routing               Health
          |                    |                     |
          +--------------------+---------------------+
                               |
                      Backend / Adapter
                         |            |
                    ssh-socks      privoxy
                         |            |
                      SOCKS5      HTTP proxy
                               |
                      Integrations
                git / docker / pip / npm
```

## 安全边界

- SOCKS 默认只监听 loopback，明确配置后才允许远程监听。
- `StrictHostKeyChecking` 默认开启。
- 不把出口 IP 当作远端 SSH 主机 IP 的必然等价物。
- 健康检查目标可配置，不依赖单一第三方 IP 服务。
- 示例配置不包含真实服务器、密钥、密码或内网地址。

## 项目状态

当前为 **v2 foundation**。Config → Routing → Backend → Adapter → Health → Integration 的边界已经建立；下一阶段重点是多 backend、容器运行时、配置 profile，以及更完整的集成测试矩阵。

许可证：MIT
