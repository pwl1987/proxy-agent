# 发布与回滚指南

当前发布模型以 `VERSION` 与 Git tag 为唯一版本边界。发布前必须让源码、CI、容器和文档保持同一版本。

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
```

当前 release workflow 在 `v*.*.*` tag 上执行 tag/VERSION 检查，并构建、发布 GHCR 镜像，随后记录镜像 digest 并生成 GitHub Release。

## 2. 创建版本

例如当前维护线：

```text
VERSION = 0.2.0
```

发布 tag：

```bash
git tag v0.2.0
git push origin v0.2.0
```

不要创建与 `VERSION` 不一致的 tag；workflow 会直接拒绝。

## 3. 镜像发布

发布 workflow 会生成：

```text
ghcr.io/<owner>/<repo>:v0.2.0
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

## 7. 版本策略

建议：

- `0.x`：快速演进，但仍要求每次发布可回滚。
- 正式稳定版：tag、CHANGELOG、镜像 digest、GitHub Release 四者对应同一版本。
- 不允许覆盖已有版本 tag。
- `latest` 只作为便利入口，不作为生产不可变引用。
