# 发布与回滚指南

当前发布模型以 `VERSION` 与 Git tag 为唯一版本边界。发布前必须让源码、CI、容器和文档保持同一版本。

当前稳定主线为 `main`，其内容对应最新正式发布版本；历史版本由不可变 Git tag 保存；版本维护工作使用对应的维护分支（如 `0.3.x`）。下一版本开发使用下一版本开发分支（如 `0.4.x`）。

## 1. 发布门槛

发布前至少确认：

```text
CI 全绿
  ↓
VERSION 正确
  ↓
Shell 语法与功能 smoke 全绿
  ↓
容器实际构建成功
  ↓
非 root 运行契约通过
  ↓
tag 与 VERSION 严格一致
  ↓
main 同步到正式发布提交
```

当前 release workflow 在 `v*.*.*` tag 上执行 tag/VERSION 检查，并构建、发布 GHCR 镜像，随后记录镜像 digest 并生成 GitHub Release。

## 2. 创建版本

例如当前稳定版本：

```text
VERSION = 0.3.0
```

发布 tag：

```bash
git tag v0.3.0
git push origin v0.3.0
```

不要创建与 `VERSION` 不一致的 tag；workflow 会直接拒绝。

发布完成后，`main` 应同步到该正式发布提交；`v0.3.0` tag 作为不可变版本边界长期保留。

不要为了“保存旧版本”而重命名 `main` 或创建仅用于保存历史的版本分支；历史正式版本优先由 Git tag 表示。只有仍需接受 bugfix/security fix 的版本系列才保留维护分支，例如 `0.3.x`。

## 3. 镜像发布

发布 workflow 会生成：

```text
ghcr.io/<owner>/<repo>:v0.3.0
ghcr.io/<owner>/<repo>:latest
```

生产环境建议固定使用版本 tag 或不可变 digest，不要仅依赖 `latest`。

## 4. 宿主机升级

系统级升级：

```bash
sudo ./upgrade.sh
```

rootless 升级：

```bash
./upgrade-user.sh
```

升级过程遵循：

```text
保存旧程序/配置/Profile/服务单元
          ↓
停止当前服务（仅原先运行时）
          ↓
安装新版本
          ↓
proxy-ctl validate
          ↓
通过 → daemon-reload → 按原状态恢复服务
失败 → 恢复旧版本 → 按原状态恢复服务
```

失败回滚不仅恢复程序目录，也恢复配置/Profile 与 systemd 单元，避免只恢复二进制而留下不匹配的服务定义。

## 5. 容器回滚

容器部署优先回滚到上一版本已验证的镜像 digest：

```text
当前 digest
   ↓
发现异常
   ↓
切回上一版本 digest
   ↓
健康检查
   ↓
确认业务恢复
```

不要在事故窗口临时重新构建“上一版本”，因为重新构建不能天然保证得到事故前使用的同一镜像内容。

## 6. 回滚后的检查

```bash
proxy-ctl status --json=v2
proxy-ctl test
proxy-ctl diagnose
proxy-ctl health-history
```

容器平台还应检查 workload replacement 是否完成，以及 Service/Ingress/端口映射是否仍指向预期实例。

## 7. 版本与分支策略

推荐采用：

```text
main
  ↓
最新稳定正式版本

0.3.x
  ↓
0.3 系列维护线

0.4.x
  ↓
0.4 系列开发线
```

规则：

- `main` 永远代表当前最新稳定发布版，并保持可发布。
- 正式版本使用不可变 Git tag，例如 `v0.3.0`。
- 仍需维护的版本系列使用对应维护分支，例如 `0.3.x`。
- 下一版本功能在对应开发分支，例如 `0.4.x`。
- feature/fix 分支应短命，通过 PR 合并后删除。
- 不允许覆盖已有版本 tag。
- `latest` 只作为便利入口，不作为生产不可变引用。

发布后的关系应保持：

```text
                 ┌── 0.3.x ── maintenance
                 │
 v0.3.0 ─────────┼── main ──── stable
                 │
                 └── 0.4.x ── development
```

对于已经 EOL 的旧版本，例如 0.2.0，只保留 `v0.2.0` tag 即可；只有存在持续维护需求时才建立或保留 `0.2.x` 维护分支。
