# proxy-agent 中文使用手册

`proxy-agent` 是 Linux 上的统一 Proxy Control Plane：负责管理代理后端、适配器、分流策略、运行状态、健康检查、应用集成，以及 systemd / rootless / container 等运行方式。

## 中文文档导航

- [CLI 参考](CLI.zh-CN.md)
- [Control API v1](CONTROL-API.md)
- [运维手册](OPERATIONS.zh-CN.md)
- [容器部署](CONTAINER.zh-CN.md)
- [Host / Container 网络](NETWORKING.zh-CN.md)
- [发布与回滚](RELEASE.zh-CN.md)

## 1. 快速开始

### 系统级部署

```bash
sudo ./install.sh
sudo editor /etc/proxy-agent/proxy-agent.conf
sudo proxy-ctl validate
sudo proxy-ctl doctor
sudo proxy-ctl start
sudo proxy-ctl status
```

### rootless 用户态部署

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

TUI 默认面向中文运维场景；按键保持稳定、不依赖终端本地化环境。

## 2. Backend

当前支持：

| Backend | 用途 | 进程归属 |
|---|---|---|
| `ssh-socks` | SSH 动态转发 + AutoSSH | proxy-agent 托管 |
| `local-endpoint` | 接入已有 HTTP/SOCKS 代理 | 外部进程，不托管 |
| `sing-box` | 托管 sing-box SOCKS 出口 | proxy-agent 托管 |
| `mihomo` | 托管 mihomo SOCKS 出口 | proxy-agent 托管 |
| `http-connect` | 接入 HTTP CONNECT 上游 | 外部上游，不托管 |

Backend contract 统一要求实现 `validate/start/stop/liveness/status/endpoint/managed/pid/process_identity/capabilities` 语义。

## 3. CLI 命令

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
proxy-ctl route <主机名或IPv4>
proxy-ctl env [--off]
proxy-ctl exec [--off] <命令> [参数...]
proxy-ctl integration <git|docker|pip|npm|all>
proxy-ctl profiles [list|show|path] [名称]
proxy-ctl capabilities
proxy-ctl health-history [--limit N] [--json]
proxy-ctl tui
```

交互式输出以中文为主；`--json` 输出保持英文字段名，以保证脚本、监控和外部系统兼容。

## 4. TUI 操作

主界面显示当前 Profile、Backend、endpoint、后端运行状态、健康状态、分流结果和常用运维操作。

快捷键：

| 按键 | 操作 |
|---|---|
| `s` | 启动代理 |
| `x` | 停止代理 |
| `r` | 重启代理 |
| `t` | 连通性测试 |
| `d` | 诊断 |
| `i` | 查看应用集成配置 |
| `R` | 查询分流策略 |
| `p` | 切换 Profile |
| `Enter` | 刷新 |
| `q` | 退出 |

## 5. Profile

每个 Profile 拥有独立的配置覆盖、runtime state、日志和 backend ownership。

```bash
proxy-ctl --profile office status
proxy-ctl --profile office start
proxy-ctl --profile office test
proxy-ctl --profile office route github.com
proxy-ctl --profile office health-history
```

## 6. Health 与恢复

健康检查分为两层：

1. **Liveness**：确认 backend 自身仍存活、监听归属正确。
2. **Network health**：通过配置的目标执行实际网络探测。

默认不会把一次外部网络故障直接判断成 backend 已死亡。自动恢复只针对明确的 backend liveness 故障。

可查看历史记录：

```bash
proxy-ctl health-history
proxy-ctl health-history --json
```

健康历史采用追加式 JSON Lines 保存，便于故障追踪与后续接入监控系统。

## 7. 路由

`route` 只解释策略，不直接修改 Linux 路由表。

支持 `exact`、`suffix`、`wildcard`、`cidr` 四类匹配；数字越小 priority 越高。

## 8. 应用集成

```bash
proxy-ctl integration git
proxy-ctl integration docker
proxy-ctl integration pip
proxy-ctl integration npm
proxy-ctl integration all
```

集成命令默认只输出建议配置，不直接修改用户系统文件。

## 9. Control API v1

系统级安装后可运行本机 Control API：

```bash
sudo systemctl enable --now proxy-agent-api.service
```

默认使用：

```text
/run/proxy-agent/control.sock
```

Control API 负责 revision、desired/observed state、apply/rollback 与 audit；不提供未经认证的远程管理入口。

详细合同见：[Control API v1](CONTROL-API.md)。

## 10. 容器

容器入口统一为：

```text
proxy-ctl run
```

容器内使用非 root `proxy-agent` 服务账户。生产部署应通过挂载或镜像派生方式提供经过验证的实际配置，不应直接使用示例配置中的占位服务器。

详细说明见：[容器部署](CONTAINER.zh-CN.md) 和 [Host / Container 网络](NETWORKING.zh-CN.md)。

## 11. 安全默认值

- SOCKS 默认绑定 `127.0.0.1`。
- SSH host key 校验默认开启。
- managed backend 停止前必须验证 PID、UID、可执行文件、命令行和监听归属。
- `local-endpoint` 与 `http-connect` 不会误杀外部代理进程。
- 配置在 `source` 前进行 ownership/mode 检查。
- systemd 使用专用低权限账户和 sandbox。
- rootless runtime/log 使用 XDG 路径。
- Control API 默认只通过 `0600` Unix socket 提供本机控制。

## 12. 发布与回滚

发布使用 tag 驱动：tag 必须与 `VERSION` 严格一致。

升级失败时，`upgrade.sh` / `upgrade-user.sh` 会恢复上一版本的程序、配置、Profile 与对应 systemd 单元；只有校验通过后才按升级前状态恢复服务。

详细流程见：[发布与回滚](RELEASE.zh-CN.md)。

## 13. 英文机器接口与中文运维界面

项目采用“双层语言策略”：

- 用户可见 CLI/TUI/运行日志/中文手册：优先中文。
- JSON schema、环境变量、backend contract、文件名和机器接口：保持英文且稳定。

这样可以兼顾国内 Linux 运维使用体验与脚本、监控、CI、第三方系统的长期兼容性。
