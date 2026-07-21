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
