# ios-build-lab

一个可复用的 iOS 构建实验仓库，先聚焦两件事：

1. 给 `Theos`/类似项目提供可重复的 GitHub Actions 构建底座
2. 以 `TrollStore` 相关构建为第一批验证对象

## 当前阶段

当前仓库先做“底座”，不急着一次覆盖全部 iOS 构建场景。

- 先打通 GitHub Actions
- 先沉淀 Theos 安装与构建脚本
- 先保留最小可维护目录结构
- 后面再按实际项目扩展

## 目录

- `.github/workflows/`：GitHub Actions 工作流
- `docs/`：设计与路线文档
- `scripts/`：环境准备、构建、收集产物脚本

## 当前工作流

### `bootstrap-theos.yml`

首版工作流先做两件事：

1. 校验仓库内脚本和目录结构
2. 在 GitHub Hosted Linux Runner 上做一次 Theos bootstrap smoke test

它的目标不是立刻完成所有项目构建，而是先验证：

- GitHub Actions 权限正常
- Linux Runner 可用
- Theos 官方安装链可以跑通
- 后续接 TrollStore/其他项目时，基础设施不是空白

### `build-external-theos.yml`

手动运行时可指定：

- GitHub 仓库（`owner/name`）
- branch、tag 或 commit
- 项目子目录
- 构建命令
- 产物 glob

工作流会安装 Theos、构建目标项目，并统一上传构建日志和匹配到的产物。默认参数构建仓库内的 `examples/hello-tool`，用于验证完整链路。

### `build-trollstore.yml`

在 GitHub Hosted macOS Runner 上构建 TrollStore。默认固定到 tag `2.1.1`，也可以手动指定其他 branch、tag 或 commit。

默认产物是核心发布包 `TrollStore.tar`。
工作流还会额外把它打包成可安装的 `.tipa`：

- 默认版：`TrollStore.tipa`
- API 版：`TrollStore-local-api.tipa`

如果把 `enable_local_api` 打开，会先对 TrollStore 应用一个本仓库维护的 overlay，产出**前台可用、监听 `127.0.0.1:48765` 的本地 HTTP API 版 TrollStore**。

如果把 `build_installers` 打开，还可以额外尝试构建：

- `_build/TrollHelper_arm64e.ipa`
- `_build/TrollHelper_iOS15.ipa`

这时需要提供：

- `victim_ipa_url`：一个可公开下载的 `InstallerVictim.ipa`
- `victim_team_id`：可选；不填时只构建 `TrollHelper_arm64e.ipa`

API 版 TrollStore 第一轮规划见：`docs/TrollStore-API方案.md`

## 下一步

1. 跑通 API 版 TrollStore 构建验收
2. 用真实设备验证 `health/apps/install/uninstall/open`
3. 再评估是否扩展 installer 线和 release 自动发布
