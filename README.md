# proxy-agent

通用 Linux Proxy Agent：统一管理代理后端、分流策略、环境变量、应用适配、健康检查与人工运维。

> 从 `devops-scripts/proxy-agent` 独立演进。新项目不再绑定具体服务器、IP、目录或单一出口。

## 目标

- **Backend 可插拔**：当前支持 SSH → SOCKS5 与现有本地 SOCKS/HTTP endpoint；后续可扩展 HTTP CONNECT、sing-box、mihomo 等。
- **Adapter 可插拔**：当前提供可选 Privoxy HTTP adapter。
- **Routing 与 Backend 解耦**：直连 / 代理由有序策略决定，而不是写死在部署脚本里。
- **安全默认值**：本地监听默认 `127.0.0.1`，SSH host key 校验默认开启。
- **应用适配**：Git、Docker、pip、npm 通过独立 integration 模块生成配置，不让主控制器继续膨胀。
- **可诊断**：`status`、`test`、`diagnose`、`route`、`doctor` 提供明确故障定位信息。
- **人工运维**：可选 TUI 提供实时状态与常用操作，不改变核心控制逻辑。
- **VM / container**：核心控制逻辑尽量无状态，systemd、Docker 等作为运行时适配层。

## 快速开始

```bash
sudo ./install.sh
sudo editor /etc/proxy-agent/proxy-agent.conf
sudo proxy-ctl doctor
sudo proxy-ctl start
sudo proxy-ctl status
sudo proxy-ctl test
```

交互式运维：

```bash
sudo proxy-ctl tui
```

当前 shell 使用代理：

```bash
eval "$(proxy-ctl env)"
```

关闭：

```bash
eval "$(proxy-ctl env --off)"
```

## Backend / Profile

当前 backend contract 已经正式落地。每个 backend 都由独立文件实现，并提供统一的 `validate/start/stop/status/endpoint/capabilities` 语义。

当前实现：

```text
ssh-socks       SSH dynamic forwarding + AutoSSH，托管 SOCKS5
local-endpoint  接管已有 HTTP/SOCKS endpoint，不拥有外部进程
```

多 Profile 可用：

```bash
proxy-ctl --profile office status
proxy-ctl --profile office test
proxy-ctl --profile office route github.com
```

systemd 下可以分别托管：

```bash
sudo systemctl enable --now proxy-agent@office.service
sudo systemctl enable --now proxy-agent-health@office.timer
```

## 配置模型

配置文件描述意图，不包含项目路径或特定机器假设。完整示例见 `proxy-agent.conf.example` 与 `profiles/example.conf`。

```bash
BACKEND="ssh-socks"
REMOTE_HOST="your-ssh-host"
REMOTE_USER="proxy"
REMOTE_PORT="22"
REMOTE_SSH_KEY="~/.ssh/id_ed25519"
SOCKS_BIND="127.0.0.1"
SOCKS_PORT="1080"

# Optional local endpoint backend
# LOCAL_PROXY_URL="http://127.0.0.1:3128"

# Optional HTTP adapter
HTTP_ENABLED="false"
HTTP_BIND="127.0.0.1"
HTTP_PORT="8118"
PRIVOXY_CONFIG="/etc/proxy-agent/privoxy.conf"

DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
DIRECT_DOMAINS="localhost,.local,.cn"
NO_PROXY_EXTRA=""

# Lower number wins
# ROUTE_RULES=$'100|DIRECT|suffix|.internal.example\n200|PROXY|wildcard|*.example.net'
```

## CLI

```text
proxy-ctl start
proxy-ctl stop
proxy-ctl restart
proxy-ctl status [--json]
proxy-ctl test
proxy-ctl diagnose
proxy-ctl doctor
proxy-ctl route <host-or-ip>
proxy-ctl env [--off]
proxy-ctl integration <git|docker|pip|npm|all>
proxy-ctl profiles [list|show|path] [name]
proxy-ctl capabilities
proxy-ctl tui
```

`route` 是策略解释命令，不会修改系统路由表。规则支持 `exact`、`suffix`、`wildcard` 和 IPv4 `cidr`，按 priority 从小到大匹配。

`status --json` 提供 schema version 1 的机器可读状态，便于外部监控或后续 TUI/运维系统复用。

## Application integrations

Integration 命令只生成配置/命令，不默认修改用户系统配置：

```bash
proxy-ctl integration git
proxy-ctl integration docker
proxy-ctl integration pip
proxy-ctl integration npm
proxy-ctl integration all
```

Git 可以直接消费 SOCKS5。Docker、pip、npm 需要 HTTP-capable active proxy path；可以启用 Privoxy，也可以选择具备 `http_native` capability 的 backend。

## HTTP adapter

默认只提供 backend 自己的 endpoint，避免额外暴露面和额外 daemon。设置 `HTTP_ENABLED=true` 后，agent 会生成并管理一个本地 Privoxy 实例，并要求 active backend 提供 `socks5` capability。

## Health / Recovery

安装 systemd 后可以按默认配置启用：

```bash
sudo systemctl enable --now proxy-agent-health.timer
```

Named Profile 使用对应的模板 timer：

```bash
sudo systemctl enable --now proxy-agent-health@office.timer
```

健康检查会按配置执行重试；失败后可自动执行一次 `proxy-ctl restart` 并再次验证。状态写入当前 Profile 的 state directory。

## 安装器

默认安装到 `/opt/proxy-agent`；也支持通过环境变量覆盖：

```bash
sudo PREFIX=/srv/proxy-agent ./install.sh
```

安装器同时部署默认与 Profile systemd templates，并保持自定义 `PREFIX` 一致。

## 安全边界

- SOCKS 默认只监听 loopback，明确配置后才允许远程监听。
- `StrictHostKeyChecking` 默认开启。
- 不把出口 IP 当作远端 SSH 主机 IP 的必然等价物。
- 健康检查目标可配置，不依赖单一第三方 IP 服务。
- 示例配置不包含真实服务器、密钥、密码或内网地址。
- `local-endpoint` 不拥有外部代理进程，不会在 `stop` 中误杀用户自行管理的代理。

## 项目状态

当前已完成 **v2 foundation + control-plane hardening**：Backend、Adapter、Routing、Profile、Health、Integration、TUI、systemd lifecycle 基础边界已经建立，并有 ShellCheck 与功能 smoke 覆盖。

下一阶段重点转向：配置 schema / 严格 validation、完整 runtime state、rootless / least-privilege、容器运行模式，以及在统一 backend contract 上增加 sing-box / mihomo 等真正有价值的后端。

许可证：MIT
