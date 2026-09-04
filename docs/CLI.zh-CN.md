# proxy-agent CLI 中文参考

## 命令总览

| 命令 | 中文用途 |
|---|---|
| `validate` | 校验配置与 Backend 合同 |
| `start` | 启动代理栈 |
| `run` | 前台运行并保持服务生命周期 |
| `stop` | 停止代理栈 |
| `restart` | 重启代理栈 |
| `status` | 查看运行状态 |
| `test` | 执行配置的连通性测试 |
| `diagnose` | 诊断依赖、配置和运行环境 |
| `doctor` | 检查危险或不一致配置 |
| `route` | 解释指定主机/IP 的分流决策 |
| `env` | 输出当前 shell 的代理环境设置 |
| `integration` | 输出 Git/Docker/pip/npm 集成配置 |
| `profiles` | 管理 Profile 查看入口 |
| `capabilities` | 查看当前 Backend 能力 |
| `health-history` | 查看健康检查历史 |
| `tui` | 启动交互式终端界面 |

## `status`

人类可读模式使用中文，例如：

```text
proxy-agent
  配置档案: office
  后端: sing-box
  后端状态: 正常监听
  endpoint: socks5h://127.0.0.1:1080
  HTTP:     已禁用
```

机器读取时继续使用稳定 JSON schema：

```bash
proxy-ctl status --json
proxy-ctl status --json=v2
```

JSON 字段名不做中文化，以避免破坏已有监控和脚本。

## `health-history`

```bash
proxy-ctl health-history
proxy-ctl health-history --json
proxy-ctl health-history --limit 50
```

文本模式适合人工排障；JSON 模式适合采集系统。

## `route`

```bash
proxy-ctl route github.com
proxy-ctl route example.cn
proxy-ctl route 10.12.34.56
```

该命令只解释策略，不修改系统路由表。

## Profile

```bash
proxy-ctl --profile office status
proxy-ctl --profile office restart
proxy-ctl --profile office health-history
```

## 环境变量

```bash
eval "$(proxy-ctl env)"
eval "$(proxy-ctl env --off)"
```

生成的变量名继续使用标准英文名称：`HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY`。
