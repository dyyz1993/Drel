# Drel Application (`Drel`)

基于 `WebBridgeKit-Framework` 构建的完整 iOS 产品宿主应用（Target、Scheme 与对外产品名均为 `Drel`）、通知服务扩展（`NotificationServiceExtension`）、UI 自动化测试套件（`DrelUITests`）及配套服务端（`Server/`）。

## 1. 仓库定位与目录结构

本工程是从原 `WebBridgeKit` 单体仓库按照 `ADR-0002` 与 `ADR-0006` 拆分出的**独立 Drel 产品工程**。`SuperApp/` 是保留的源码目录名；工程、target、workspace、scheme 与产品名统一使用 Drel：

- **`SuperApp/`**：完整产品宿主源码（首页、收信箱 Inbox、PWA 应用中心、发现页、设置、审批流、展示目录）与资源。
- **`NotificationServiceExtension/`**：独立 APNs 通知扩展（负责 `PushCipher` 对称加密消息与 `drel.push-envelope.v1` X25519 自托管信封的端到端解密及自定义头像处理，零 CocoaPods 依赖）。
- **`DrelUITests/`**：28 个 XCUITest 端到端与 UI 保真度测试套件。
- **`Server/`**：Swift 6 + Hummingbird 2 推送与网关后端（`:8080`）、Go 原生自托管服务端（`Server/native/`）及 Node 管理后台（`Server/node/`）。
- **`deploy/` & `infra/`**：网关 Nginx 配置与 Cloudflare Worker 边缘代理（`infra/cloudflare/drel-api-proxy/`）。
- **`tools/` & `scripts/`**：应用层发布门禁、真机冒烟、容器安全策略校验与本地三服务管理脚本。

> 底层 SDK 源码（`Sources/`）、框架资源（`Resources/`）、最小模板（`AppTemplate/`）及框架单元测试（`Tests/`）位于同级目录的 `../WebBridgeKit-Framework` 工程中。

## 2. 环境准备与联调构建

默认约定将 `WebBridgeKit-Framework` 与 `Drel` 并列放置在同一父目录下（可通过环境变量 `WBK_FRAMEWORK_PATH` 自定义底层框架路径）：

```bash
# 1. 生成 Xcode 工程并安装依赖（自动关联 ../WebBridgeKit-Framework）
xcodegen generate
pod install

# 2. 启动本地配套测试服务（:8080 后端 / :8081 静态资源 / :8083 原型）
bash scripts/services.sh start
bash scripts/services.sh verify

# 3. 编译 Drel
xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/drel-app-dd

# 4. 运行应用层门禁与协议校验
bash tools/verify-deliverable-boundaries.sh
bash tools/architecture-lint.sh --ci
bash tools/design-lint.sh --ci
bash tools/verify-drel-container-only.sh
bash tools/verify-drel-release-settings.sh
bash tools/verify-drel-critical-alert-policy.sh
bash tools/verify-apns-single-attempt.sh
bash tools/verify-node-admin-local.sh
```

## 3. 应用层启动注入配置

在 `SuperApp/Sources/AppDelegate.swift` 启动阶段，应用层显式向底层框架注入产品命名空间与策略：

- `PushCipher.configure(appGroup: "group.com.webbridgekit.superapp", keychainService: "com.webbridgekit.superapp.push-crypto")`
- `SelfHostedPushCrypto.configure(appGroup: "group.com.webbridgekit.superapp")`
- `HTMLAppGatewayDefaults.configureOfficial(...)`
- `WebBridgeHostCapabilityPolicy.containerOnlyOverride`（跟随应用层 `#if DREL_CONTAINER_ONLY` 编译宏）

## 4. 开发规范与底层问题协作排障指南

完整的开发规范、代码质量门禁以及《应用层遇到底层框架问题的标准排查与处理 SOP》请查阅：
- `docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md`
