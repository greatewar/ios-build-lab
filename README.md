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

## 下一步

1. 运行外部项目构建样例
2. 固化验证结果和依赖
3. 接入 TrollStore 作为第一个真实目标
