# 功能迭代日志

> 记录每个稳定版本及关键架构迭代的实际功能、依赖调用链、状态边界、验证结果与发布治理。只记录已经进入代码并被门禁验证的事实；计划项必须明确标为未完成。

## 版本记录规则

每个功能版本至少记录：版本/基线提交、功能增量、模块调用链、状态与并发边界、兼容性、实际 CI/Smoke/Functional/Upgrade 门禁、发布 Tag/Release/镜像及遗留事项。

## 0.4.x：生命周期与控制面收口

- `proxy-ctl` 生命周期命令采用串行化执行，生命周期锁作为权威并发边界。
- Revision Store、Audit Store、Reconciler 保持职责分离，避免新增第二套状态来源。
- 生命周期、revision、audit、reconcile、health recovery 纳入持续 smoke 门禁。

核心链路：

```text
proxy-ctl lifecycle
  -> lifecycle lock
  -> revision/audit state
  -> reconciler
  -> runtime state
  -> health recovery
```

## 0.5.0：Egress Path Foundation

- 引入 typed `egress_path`，首先落地 direct SSH path。
- `lib/typed-legacy-export.py` 将 typed 配置投影到现有 legacy runtime 配置。
- `backends/ssh-socks.sh` 保持现有 PID、listener、AutoSSH keepalive、strict host-key、cleanup ownership 等行为。
- path 变化接入 revision/reconcile/Control API 边界，没有建立平行状态仓库。

调用链：

```text
typed config
  -> typed-legacy-export
  -> legacy runtime config
  -> proxy-ctl validation/lifecycle
  -> ssh-socks backend
  -> runtime/revision/reconcile
  -> Control API
```

## 0.5.1：SSH Jump / Identity / Path Health

- 落地 one-hop SSH Jump foundation。
- 增加可选 `backend_health_detail` contract。
- ssh-socks health 拆成 `transport/jump/target/proxy/overall`，并记录 `reason`、`last_checked`。
- Jump 不可达时表达为 `jump=failed / target=unknown`，避免把中间跳点故障误报为 target failure。
- `runtime.json` status v2 增加 `health.path`。
- `health-history` 持久化因果 reason。
- status query 不主动 probe SSH，由 health runner 负责 probe 和 observation sync。
- 增加 Path Health smoke，和既有 Functional / ShellCheck / Upgrade Transaction Gate 一起形成发布门禁。

调用链：

```text
health runner
  -> backend probe
  -> backend_health_detail
  -> runtime status v2 / health.path
  -> health-history
  -> Control API status read
```

## 0.5.2：Web Gateway Foundation

`main` 已包含 Web Gateway foundation，但该代码不属于 `v0.5.1` 发布物；0.5.1 provenance 收口之前冻结 0.5.2 发布。

已进入代码的能力：

- `bin/proxy-agent-web`
- loopback 默认监听
- Bearer token
- 非 loopback 场景要求 TLS
- 通过 Unix socket 只读代理 Control API v1
- mutating methods 拒绝
- `no-store`
- Web Gateway smoke

后续 0.5.2 迭代按“功能 -> 调用链 -> 状态影响 -> 安全边界 -> 兼容性 -> 验证 -> 发布物”登记。

## 发布治理：v0.5.1 provenance 纠偏

本次 0.5.1 发布暴露出 Tag、构建源和 Release 可能分离的问题：最初 Tag 位于 bootstrap commit，随后分支清理了临时 workflow。如果构建继续 checkout 分支，会出现“Release 成功但发布物并非严格由 Tag 构建”的风险。

最终约束固定为：

```text
Release Tag
    == source commit
    == container build source
    == release-provenance.txt source
    == published image provenance
```

永久 release workflow 必须：

1. 按 Tag checkout，而不是按当前分支 checkout。
2. 打印 event/ref/ref_name/run id。
3. 打印 Tag target、HEAD、tree、commit metadata，并验证 HEAD == Tag target、工作树 clean。
4. 校验 Tag 版本与 `VERSION` 一致。
5. 打印 version image digest 与 latest digest。
6. 生成 `container-digest.txt` 和 `release-provenance.txt`。
7. 在 Release 中上传 provenance asset。
8. Release 创建后再次打印 Release URL、Tag、assets 状态。

### 0.5.1 修复结果

修复后的 `v0.5.1` 指向 clean release commit `3f4108e0c1d758bc2d093c8b89d0f45329ef7d86`；构建流程已实际 checkout 该 Tag，Tag/source consistency、源码校验、容器构建、GHCR push、Release recreate 全部成功。

发布 provenance：

```text
source_commit=3f4108e0c1d758bc2d093c8b89d0f45329ef7d86
source_tree=ce39d41f6659ad7dd5271d93a7a5841accb9e769
image_digest=sha256:6e2a83452cdf89c41d3e95230356eda8a9224dc2528c475ed8d4c66f922f3580
workflow_run_id=33960045760
```

Release 同时保存 `container-digest.txt` 与 `release-provenance.txt`，用于从发布物反查源码来源。

## 下一步治理原则

- 稳定版本 Tag 一旦发布，不允许用分支 HEAD 代替 Tag 作为构建源。
- 临时 release workflow 必须在发布物形成前后明确生命周期，并不得混入稳定 Tag。
- 功能日志与 Release 日志分开维护：功能日志回答“做了什么、为什么这样做、影响了哪些链路”，Release provenance 回答“这个发布物究竟从哪里构建出来”。
- `main` 可以承载下一版本开发代码，但稳定版本必须通过独立 release baseline、VERSION、Tag、CI 和发布 provenance 收口。
