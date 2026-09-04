# proxy-agent

通用 Linux Proxy Agent：统一管理代理后端、分流策略、环境变量、应用集成与健康检查。

> 从 `devops-scripts/proxy-agent` 独立演进。新项目不再绑定具体服务器、IP、目录或单一出口。

## 目标

- **Backend 可插拔**：当前支持 SSH → SOCKS5，后续可扩展 HTTP CONNECT、sing-box、mihomo 等。
- **Routing 与 Backend 解耦**：直连 / 代理由策略决定，而不是写死在部署脚本里。
- **安全默认值**：本地监听默认 `127.0.0.1`，SSH host key 校验默认开启。
- **应用集成**：Git、curl、Docker、pip、npm 等通过统一配置生成代理环境。
- **可诊断**：`status`、`test`、`diagnose`、`route` 提供明确故障定位信息。
- **VM / container**：核心逻辑尽量无状态，systemd、Docker 等作为运行时适配层。

## 快速开始

```bash
sudo ./install.sh
sudo cp /etc/proxy-agent/proxy-agent.conf.example /etc/proxy-agent/proxy-agent.conf
sudo editor /etc/proxy-agent/proxy-agent.conf
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

配置文件只描述意图，不包含项目路径或特定机器假设：

```bash
BACKEND=ssh-socks
REMOTE_HOST="proxy.example.com"
REMOTE_USER="proxy"
REMOTE_PORT=22
REMOTE_SSH_KEY="~/.ssh/id_ed25519"
SOCKS_BIND=127.0.0.1
SOCKS_PORT=1080
HTTP_ENABLED=true
HTTP_PORT=8118

DIRECT_CIDRS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
DIRECT_DOMAINS="localhost,.local,.cn"

HEALTH_TARGETS="https://github.com,https://pypi.org,https://registry.npmjs.org"
```

## CLI

```text
proxy-ctl start
proxy-ctl stop
proxy-ctl restart
proxy-ctl status
proxy-ctl test
proxy-ctl diagnose
proxy-ctl route <host>
proxy-ctl env [--off]
proxy-ctl add-domain <domain>
proxy-ctl doctor
proxy-ctl uninstall
```

## 架构

```text
                    +----------------------+
                    |      proxy-ctl       |
                    +----------+-----------+
                               |
              +----------------+----------------+
              |                |                |
          Config           Routing          Health
              |                |                |
              +----------------+----------------+
                               |
                       Backend interface
                               |
                    +----------+-----------+
                    |                      |
               ssh-socks              future...
                    |
              autossh / ssh
                    |
                  SOCKS5
                    |
             optional HTTP proxy
```

## 安全边界

- SOCKS 默认只监听 loopback，明确配置后才允许远程监听。
- 不使用 `StrictHostKeyChecking=no` 作为默认策略。
- 不把出口 IP 当作远端 SSH 主机 IP 的必然等价物。
- 健康检查目标可配置，不依赖单一第三方 IP 服务。
- 示例配置不包含真实服务器、密钥、密码或内网地址。

## 项目状态

当前为 **v2 foundation**：先把原型中已经验证的 SSH/SOCKS/HTTP 能力迁移到通用边界，再逐步增加更多 backend 与平台适配器。

许可证：MIT
