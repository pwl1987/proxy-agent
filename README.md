# proxy-agent

通用 Linux Proxy Agent：统一管理代理后端、分流策略、环境变量、应用适配、健康检查与人工运维。

> 从 `devops-scripts/proxy-agent` 独立演进。新项目不再绑定具体服务器、IP、目录或单一出口。

## 目标

- **Backend 可插拔**：当前支持 SSH → SOCKS5 与现有本地 SOCKS/HTTP endpoint；后续可扩展 HTTP CONNECT、sing-box、mihomo 等。
- **Adapter 可插拔**：当前提供可选 Privoxy HTTP adapter。
- **Routing 与 Backend 解耦**：直连 / 代理由有序策略决定，而不是写死在部署脚本里。
- **安全默认值**：本地监听默认 `127.0.0.1`，SSH host key 校验默认开启。
- **应用适配**：Git、Docker、pip、npm 通过独立 integration 模块生成配置，不让主控制器继续膨胀。
- **可诊断**：`status`、`test`、`diagnose`、`route`、`doctor`、`validate` 提供明确故障定位信息。
- **人工运维**：可选 TUI 提供实时状态与常用操作，不改变核心控制逻辑。
- **VM / container**：核心控制逻辑尽量无状态，systemd、Docker 等作为运行时适配层。

## 快速开始

系统级部署：

```bash
sudo ./install.sh
sudo editor /etc/proxy-agent/proxy-agent.conf
sudo proxy-ctl validate
sudo proxy-ctl doctor
sudo proxy-ctl start
sudo proxy-ctl status
sudo proxy-ctl test
```

rootless 用户态部署：

```bash
./install-user.sh
$EDITOR "${XDG_CONFIG_HOME:-$HOME/.config}/proxy-agent/proxy-agent.conf"
proxy-ctl validate
proxy-ctl doctor
proxy-ctl start
proxy-ctl status --json=v2
```

完整 rootless 部署说明见 `docs/ROOTLESS.md`。

交互式运维：

```bash
proxy-agent-tui
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

当前 backend contract 已经正式落地。每个 backend 都由独立文件实现，并提供统一的 `validate/start/stop/status/endpoint/managed/pid/process_identity/capabilities` 语义。

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

系统级 systemd：

```bash
sudo systemctl enable --now proxy-agent@office.service
sudo systemctl enable --now proxy-agent-health@office.timer
```

rootless user systemd：

```bash
systemctl --user enable --now proxy-agent@office.service
systemctl --user enable --now proxy-agent-health@office.timer
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

所有配置在 activation 前都通过 `proxy-ctl validate` 进行 schema 与 cross-field 检查。系统部署的配置必须是受保护文件；rootless 配置默认由当前用户私有持有。

## CLI

```text
proxy-ctl validate
proxy-ctl start
proxy-ctl run
proxy-ctl stop
proxy-ctl restart
proxy-ctl status [--json|--json=v2]
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

`status --json` 提供 schema version 1 的兼容状态；`status --json=v2` 提供包含 backend、adapter、health、lifecycle 与 ownership 信息的运行时状态。

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

默认只提供 backend 自己的 endpoint，避免额外暴露面和额外 daemon。设置 `HTTP_ENABLED=true` 后，agent 会生成并管理一个本地 Privoxy 实例，并要求 active backend 提供 `socks5` capability。生成配置保存在 profile runtime state，不直接修改系统 `/etc` 配置。

## Health / Recovery

健康检查会按配置执行重试；失败后可自动执行一次 `proxy-ctl restart` 并再次验证。健康 marker 与 runtime state 保存在当前 Profile 的 state directory。

系统级 systemd：

```bash
sudo systemctl enable --now proxy-agent-health.timer
sudo systemctl enable --now proxy-agent-health@office.timer
```

rootless user systemd：

```bash
systemctl --user enable --now proxy-agent-health.timer
systemctl --user enable --now proxy-agent-health@office.timer
```

## 安装器

默认系统安装到 `/opt/proxy-agent`，由专用 `proxy-agent` service account 运行：

```bash
sudo PREFIX=/srv/proxy-agent ./install.sh
```

rootless 用户安装：

```bash
./install-user.sh
```

rootless 安装默认使用 XDG 配置、runtime 和日志目录，也支持通过 `PREFIX`、`BIN`、`XDG_CONFIG_HOME` 覆盖布局。user systemd 没有活动 session 时，安装器仍完成文件部署，不会因缺少 user bus 而失败。

## 安全边界

- SOCKS 默认只监听 loopback，明确配置后才允许远程监听。
- `StrictHostKeyChecking` 默认开启。
- 不把出口 IP 当作远端 SSH 主机 IP 的必然等价物。
- 健康检查目标可配置，不依赖单一第三方 IP 服务。
- 示例配置不包含真实服务器、密钥、密码或内网地址。
- 配置被 `source` 前检查 ownership/mode，避免可写配置变成代码执行入口。
- systemd 系统部署使用专用账户与 filesystem/process sandbox。
- rootless user services 使用同一 sandbox，并把 runtime state/log 放在 `%t` 以兼容 `ProtectHome=read-only`。
- `local-endpoint` 不拥有外部代理进程，不会在 `stop` 中误杀用户自行管理的代理。

## 项目状态

当前已完成 **v2 foundation + control-plane + runtime + deployment hardening + rootless operator gate**。Backend、Adapter、Routing、Profile、Health、Integration、TUI、配置校验、runtime state、生命周期 ownership、系统级最小权限与 rootless 用户态部署均已落地，并有 ShellCheck、Syntax、systemd contract 和功能 smoke 覆盖。

下一阶段重点转向：**backend compatibility**。首先把 backend liveness 与 network health probe 解耦，然后建立 backend/adapter compatibility matrix，再在统一 contract 上评估 sing-box、mihomo 与 HTTP CONNECT，而不是在基础层继续堆功能。

许可证：MIT
