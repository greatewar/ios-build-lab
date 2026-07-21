# TrollStore API 方案

## 当前目标

不是继续讨论 WDA，也不是继续折腾 TrollStore installer。

当前主线是：

- 让 AI 可以调用 TrollStore
- 至少实现安装 IPA、卸载 App、查询列表、打开 App
- 尽量减少人工介入

## 第一版边界

先做一个**前台运行时可用**的 API 版 TrollStore，不追求后台常驻。

原因：

- 非越狱环境下，后台常驻会明显放大复杂度
- 先把“AI 能自动装 / 卸 / 查”这条链路跑通，收益最高
- 用户已经明确接受“App 在前台时可用”

## 通信模型

第一版只监听 **iPhone 本机回环地址 `127.0.0.1`**，不直接暴露到局域网。

这样做的原因：

- 不需要额外本地网络权限弹窗
- 默认不暴露给同网段其他设备
- 后续可以通过 USB 端口转发把电脑流量转到手机本地端口

典型链路：

1. 手机前台打开 API 版 TrollStore
2. TrollStore 在 `127.0.0.1:48765` 监听
3. 电脑侧用 `tidevice relay` / `usbmux` 类工具做端口转发
4. AI 调本机 `http://127.0.0.1:<forwarded-port>` 完成安装、卸载、查询

## 为什么不用 “手机自己下载 IPA URL”

第一版主推 **HTTP 直接上传 IPA 二进制**，而不是强依赖手机去下载远程 URL。

原因：

- 电脑本来就拿得到本地 IPA 文件
- 不依赖手机额外联网、ATS、下载源稳定性
- 更适合 AI 自动化：直接把文件 POST 给 TrollStore 即可

## API 草案

### `GET /health`

返回服务是否存活、端口、版本。

### `GET /apps`

返回 TrollStore 已安装应用列表，至少包含：

- `bundle_id`
- `name`
- `version`
- `path`
- `registration_state`

### `POST /install?filename=xxx.ipa&force=1`

- 请求体：IPA 原始二进制
- 行为：落临时文件 -> 调 `TSApplicationsManager installIpa`
- 返回：`code`、`message`、`log`

### `POST /uninstall?bundle_id=com.example.app`

- 行为：调 `TSApplicationsManager uninstallApp`
- 返回：`code`、`message`

### `POST /open?bundle_id=com.example.app`

- 行为：调 `TSApplicationsManager openApplicationWithBundleID`
- 返回：是否成功

## 代码落点

优先最小侵入：

- 先只改 `TrollStore/TSAppDelegate.m`
- 不先扩大量新文件
- 不先改设置页 UI

这样可以减少：

- Theos 目标改动面
- Makefile 改动面
- 上游合并冲突面

## 构建策略

不直接把 TrollStore 全源码塞进 `ios-build-lab`。

而是：

- 保持 `ios-build-lab` 继续 checkout 上游 TrollStore
- 在 workflow 里增加一个“应用 API overlay”的步骤
- 用本仓库里的 overlay 文件覆盖上游对应源码
- 再走原本的构建链

这样方便：

- 跟踪上游版本
- 明确区分“上游源码”和“我们的改动”
- 后续切换开 / 关 API 变体

## 第一轮验收标准

只要满足下面 4 条，就算第一轮成功：

1. GitHub Actions 能成功构建 API 版 TrollStore
2. TrollStore 打开后能监听本机 `127.0.0.1:48765`
3. `GET /health` 和 `GET /apps` 能返回 JSON
4. `POST /install` / `POST /uninstall` 能调用现有 TrollStore 安装卸载能力

## 安装交付形态

为了让用户能直接在现有 TrollStore 上安装，本仓库不会只停留在 `TrollStore.tar`。

工作流还会把产物再包装成：

- 普通版：`TrollStore.tipa`
- API 版：`TrollStore-local-api.tipa`

这样用户可以直接：

1. 把 `.tipa` 传到手机
2. 用现有 TrollStore 打开
3. 点安装 / 覆盖安装

## 当前验证结果

- GitHub Actions Run `29855361459`：`enable_local_api=true` 的 API overlay 版 TrollStore 编译成功
- GitHub Actions Run `29855945988`：在上面的基础上继续验证 `.tipa` 打包成功
- 产物包含：
  - `_build/TrollStore.tar`
  - `_build/TrollStore-local-api.tipa`
- `TrollStore-local-api.tipa` 大小：`2,462,236` bytes
- `TrollStore-local-api.tipa` SHA256：`5532685d35306ea5709ac90bf776d59b83703d4233c87f3daceefd72b7905ece`

## 暂时不做

- 后台常驻
- 局域网公开监听
- 复杂鉴权
- 大而全的 REST 设计
- 和 WDA 联动
