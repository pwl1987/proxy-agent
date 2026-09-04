# proxy-agent 中文运维手册

## 一、运行模型

`proxy-agent` 不再只是一个 SSH 隧道脚本，而是 Linux 上的统一代理控制平面。

```text
                 ┌──────────────────────────┐
                 │       proxy-ctl / TUI     │
                 └────────────┬─────────────┘
                              │
             ┌────────────────┼────────────────┐
             │                │                │
          Backend          Adapter          Route
             │                │                │
     SSH / sing-box /     Privoxy HTTP      DIRECT/PROXY
     mihomo / endpoint
             │
        Runtime State
             │
       Health / Recovery
```

核心原则：Backend 负责出口能力，Adapter 负责协议转换，Route 负责策略判断，Profile 负责隔离，Runtime State 负责可观测状态。

## 二、推荐目录

系统安装：

```text
/opt/proxy-agent/              程序
/etc/proxy-agent/              配置
/run/proxy-agent/              运行状态
/var/log/proxy-agent/          日志
```

rootless 安装遵循 XDG 目录；user systemd 的 runtime/log 默认放到 `%t/proxy-agent`。

## 三、启动前检查

```bash
proxy-ctl validate
proxy-ctl doctor
proxy-ctl diagnose
proxy-ctl capabilities
proxy-ctl status --json=v2
```

看到配置错误时先修复 `validate`，看到安全问题时先修复 `doctor`，依赖或运行环境异常使用 `diagnose`。

## 四、启动与停止

系统服务：

```bash
sudo systemctl enable --now proxy-agent.service
sudo systemctl status proxy-agent.service
sudo systemctl restart proxy-agent.service
sudo systemctl stop proxy-agent.service
```

Profile：

```bash
sudo systemctl enable --now proxy-agent@office.service
sudo systemctl enable --now proxy-agent-health@office.timer
```

rootless：

```bash
systemctl --user enable --now proxy-agent.service
systemctl --user enable --now proxy-agent@office.service
```

容器：

```text
proxy-ctl run
```

容器中不要通过 systemd 管理进程；让 `proxy-ctl run` 作为唯一前台生命周期进程。

## 五、健康检查

健康状态至少分成三种语义：

- 后端存活：进程、PID、UID、可执行文件、命令行和监听归属一致。
- 网络健康：通过配置的目标执行实际代理链路探测。
- 恢复状态：后端死亡触发受控 restart 后再次验证。

检查历史：

```bash
proxy-ctl health-history
proxy-ctl health-history --limit 50
```

程序采集使用：

```bash
proxy-ctl health-history --json
```

JSON 行的字段名保持稳定英文；人工输出为中文。

## 六、常见故障

### 1. 端口已经被占用

先执行：

```bash
proxy-ctl diagnose
ss -lntp
```

不要直接 kill 未确认归属的 PID。managed backend 必须先验证进程 ownership。

### 2. 后端正常但外网探测失败

优先区分 backend liveness 与 network health。`HEALTH_NETWORK_REQUIRED=false` 时，网络探测失败不应该自动把本地 backend 判死。

### 3. HTTP 适配器无法启动

确认 active backend 提供 `socks5` capability，再检查：

```bash
command -v privoxy
proxy-ctl capabilities
proxy-ctl validate
```

### 4. SSH 后端启动失败

检查：

```bash
proxy-ctl diagnose
ssh -v <用户>@<主机>
```

确认 host key 校验没有被关闭，并确认密钥和远端账号正确。

## 七、发布与升级

发布只能由版本 tag 触发，并要求 tag 与仓库 `VERSION` 完全一致。

升级顺序：

```text
停止当前实例
  ↓
安装新版本
  ↓
验证新版本配置与依赖
  ↓
恢复原运行状态
  ↓
健康检查
```

验证失败时不得恢复服务到未验证版本；应回滚到上一份已知可运行版本。

## 八、中文界面原则

所有面向人的操作路径优先中文：

- TUI 标题、状态、快捷键说明、交互提示
- CLI 的人类可读状态和诊断信息
- 健康历史表格
- 中文安装/部署/故障排查文档

所有面向程序的接口保持稳定：

- JSON 字段
- 环境变量
- backend contract
- schema version
- 配置键名
- 文件和命令名

因此中文化不会破坏已有自动化脚本。
