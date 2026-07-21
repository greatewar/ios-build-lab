# TrollStore 方向

这个仓库会把 TrollStore 当成第一批验证对象，但不把仓库本身绑死成 TrollStore 专用仓库。

## 先做什么

1. 先验证 GitHub Actions Linux Runner 能稳定准备 Theos
2. 再验证外部项目 checkout + 依赖准备
3. 最后再接 TrollStore 项目本身

## 为什么不一开始直接硬上 TrollStore

- 先把 CI 底座搭好，后续才能反复试错
- 先分离“环境问题”和“项目问题”
- 避免第一次提交里同时处理 workflow、Theos、TrollStore 三类变量

## 预期后续输入

后面可以给 workflow 增加这些输入：

- `target_repo`
- `target_ref`
- `target_subdir`
- `build_command`
- `artifact_glob`

## 实际构建边界

TrollStore 的 `fastPathSign` 和 `pwnify` 是 macOS 主机工具，不能在 Linux runner 上原样编译。因此 TrollStore 使用独立的 `macos-14` workflow，但继续复用仓库里的 Theos bootstrap 和统一产物收集脚本。

第一阶段只构建 `_build/TrollStore.tar`。官方源码没有提交 `Victim/InstallerVictim.ipa`，所以 `TrollHelper_iOS15.ipa` 和 `TrollHelper_arm64e.ipa` 不纳入这一轮；它们需要单独准备 victim IPA 后再验证。

现在仓库已经补上 installer 输入接口：

- `build_installers=true` 时启用 installer 构建分支
- `victim_ipa_url` 用来下载 `Victim/InstallerVictim.ipa`
- `victim_team_id` 可选；提供后才会额外构建 `TrollHelper_iOS15.ipa`

也就是说，当前边界已经从“不能接 installer 输入”推进到“可以接输入，但还需要真实 victim IPA 做正向验收”。

已做一轮反向验收：

- GitHub Actions Run `29851949839`
- `build_installers=true` 且 `victim_ipa_url` 留空
- 结果按预期在 `Prepare victim IPA inputs` 步骤提前失败，并给出明确报错：`victim_ipa_url is required when build_installers=true`

## API 方向

现在已经把新主线切回 TrollStore API：

- `build-trollstore.yml` 新增 `enable_local_api`
- 打开后会先应用 `overlays/trollstore-api/` 下的 overlay
- 第一版只做**前台运行时可用**、监听 `127.0.0.1:48765` 的本地 HTTP API
- 工作流会把 `TrollStore.tar` 再包装成可直接在现有 TrollStore 里安装的 `.tipa`
- 详细设计见 `docs/TrollStore-API方案.md`

## 这一轮踩到的坑

- GitHub `macos-14` runner 自带的是 Bash 3.2，不支持 `shopt -s globstar`
- 因此通用产物收集脚本不能依赖 `globstar` 展开 `**` 模式
- 当前做法改成用 Python `glob.glob(..., recursive=True)` 展开 artifact glob，兼容 macOS runner
