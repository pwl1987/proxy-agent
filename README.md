# proxy-agent

Linux 统一 Proxy Control Plane：统一管理代理后端、适配器、分流策略、Profile、运行状态、健康检查、应用集成，以及 systemd / rootless / container 运行方式。

## 中文文档

中文运维入口：[`docs/README.zh-CN.md`](docs/README.zh-CN.md)

中文 CLI 参考：[`docs/CLI.zh-CN.md`](docs/CLI.zh-CN.md)

中文运维手册：[`docs/OPERATIONS.zh-CN.md`](docs/OPERATIONS.zh-CN.md)

下一阶段架构：[`docs/ARCHITECTURE-NEXT.zh-CN.md`](docs/ARCHITECTURE-NEXT.zh-CN.md)

容器部署：[`docs/CONTAINER.zh-CN.md`](docs/CONTAINER.zh-CN.md)

Host / Container 网络：[`docs/NETWORKING.zh-CN.md`](docs/NETWORKING.zh-CN.md)

发布与回滚：[`docs/RELEASE.zh-CN.md`](docs/RELEASE.zh-CN.md)

Control API v1：[`docs/CONTROL-API.md`](docs/CONTROL-API.md)

> 项目采用“双层语言策略”：面向人的 CLI/TUI/运维文档默认中文；JSON schema、环境变量、backend contract 和机器接口保持稳定英文。

## 当前能力

- **Backend 可插拔**：SSH SOCKS5、现有本地 endpoint、sing-box、mihomo、HTTP CONNECT。
- **Adapter 可插拔**：可选 Privoxy，把 SOCKS5 能力转换为本地 HTTP 代理。
- **Routing 与 Backend 解耦**：exact / suffix / wildcard / IPv4 CIDR 有序规则。
- **Profile 隔离**：配置、runtime state、日志和 backend ownership 均可按 Profile 隔离。
- **生命周期统一**：`proxy-ctl run` 同时服务于 systemd 和 container 前台运行模式。
- **健康语义分层**：backend liveness 与实际 network health 分离，并支持受控自动恢复。
- **可观测性**：`status --json=v2` 与追加式 health-history JSONL。
- **控制面**：本地 Control API v1 提供 revision、desired/observed state、apply/rollback 和 audit。
- **安全默认值**：本地代理默认绑定 `127.0.0.1`；托管 backend 停止前验证进程 ownership。
- **运维 TUI**：中文终端控制台提供状态、测试、诊断、分流和 Profile 操作。

## 快速开始

### 系统级部署

```bash
sudo ./install.sh
sudo editor /etc/proxy-agent/proxy-agent.conf
sudo proxy-ctl validate
sudo proxy-ctl doctor
sudo proxy-ctl start
sudo proxy-ctl status
```

### rootless

```bash
./install-user.sh
$EDITOR "${XDG_CONFIG_HOME:-$HOME/.config}/proxy-agent/proxy-agent.conf"
proxy-ctl validate
proxy-ctl doctor
proxy-ctl start
proxy-ctl status --json=v2
```

### TUI

```bash
proxy-agent-tui
```

### 在当前 shell 启用代理

```bash
eval "$(proxy-ctl env)"
```

关闭：

```bash
eval "$(proxy-ctl env --off)"
```

## Backend 与 Profile

所有 Backend 采用统一 contract：

```text
validate / start / stop / liveness / status / endpoint
managed / pid / process_identity / capabilities
```

示例：

```bash
proxy-ctl --profile office status
proxy-ctl --profile office start
proxy-ctl --profile office test
proxy-ctl --profile office route github.com
```

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
proxy-ctl exec [--off] <command> [args...]
proxy-ctl integration <git|docker|pip|npm|all>
proxy-ctl profiles [list|show|path] [name]
proxy-ctl capabilities
proxy-ctl health-history [--limit N] [--json]
proxy-ctl tui
```

普通人类可读输出默认使用中文；`--json` 仍输出稳定英文 schema，不用于人类显示。

## Health / Recovery

健康检查依次区分：

1. Backend liveness：进程、PID、UID、可执行文件、命令行和监听归属。
2. Network health：通过配置目标验证真实代理链路。
3. Recovery：仅对明确的 liveness 故障执行受控重启。

查看历史：

```bash
proxy-ctl health-history
proxy-ctl health-history --json
```

## Routing

`route` 只解释策略，不修改系统路由表。

```bash
proxy-ctl route github.com
proxy-ctl route example.cn
proxy-ctl route 10.12.34.56
```

## Application integrations

```bash
proxy-ctl integration git
proxy-ctl integration docker
proxy-ctl integration pip
proxy-ctl integration npm
proxy-ctl integration all
```

默认只生成建议配置，不直接修改用户系统文件。

## Deployment

系统级 systemd：

```bash
sudo systemctl enable --now proxy-agent.service
sudo systemctl enable --now proxy-agent-health.timer
```

Profile systemd：

```bash
sudo systemctl enable --now proxy-agent@office.service
sudo systemctl enable --now proxy-agent-health@office.timer
```

rootless user systemd：

```bash
systemctl --user enable --now proxy-agent.service
systemctl --user enable --now proxy-agent-health.timer
```

容器采用非 root `proxy-agent` 用户，并以 `proxy-ctl run` 作为前台唯一生命周期进程。

Control API systemd：

```bash
sudo systemctl enable --now proxy-agent-api.service
```

默认监听：

```text
/run/proxy-agent/control.sock
```

详见 [`docs/CONTROL-API.md`](docs/CONTROL-API.md)。

## 安全边界

- SOCKS 默认只监听 loopback。
- SSH host key 校验默认开启。
- managed backend 停止前验证 PID / UID / executable / command line / listener ownership。
- `local-endpoint` 和 `http-connect` 不拥有外部代理进程。
- `source` 配置之前检查 ownership / mode。
- systemd 使用专用低权限账户和 sandbox。
- rootless 使用 XDG 路径。
- Control API 默认只通过 `0600` Unix socket 提供本机控制。

## Release engineering

版本发布采用 tag 驱动，tag 必须与 `VERSION` 严格一致：

```text
main CI
  ↓
tag v0.2.x
  ↓
VERSION/tag consistency
  ↓
container build
  ↓
GHCR push
  ↓
immutable digest capture
  ↓
GitHub Release
```

升级流程会先安装并验证新版本，再恢复原运行状态；失败时不得把服务切换到未验证版本。

## 开发验证

CI 包含：

- ShellCheck
- Bash syntax
- Backend contract smoke
- HTTP CONNECT smoke
- Control API / revision / reconciler smoke
- Control API validation / activation failure smoke
- Container / systemd / rootless contract smoke
