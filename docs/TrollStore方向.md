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
