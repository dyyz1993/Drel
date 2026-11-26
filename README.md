# Drel Application (`Drel`)

中文 | [English](README.en.md)

基于 `WebBridgeKit-Framework` 构建的完整 iOS 产品宿主应用（Target、Scheme 与对外产品名均为 `Drel`）、通知服务扩展（`NotificationServiceExtension`）、UI 自动化测试套件（`DrelUITests/`）及配套服务端（`Server/`）。

Drel 是一个开源（MIT）项目：它把「HTML 应用运行容器 + Bark 兼容推送」的完整产品层公开出来，底层 SDK [`WebBridgeKit-Framework`](../WebBridgeKit-Framework) 同样以 MIT 开源，两仓库按并列目录约定协同构建。

## 快速开始

| 你想做的事 | 从这里开始 |
|---|---|
| 了解产品与仓库结构 | [第 1 节](#1-仓库定位与目录结构) |
| 编译并跑起来 | [第 2 节](#2-环境准备与联调构建) |
| 查完整文档地图 | [docs/README.md](docs/README.md) |
| 看每个版本的变更 | [CHANGELOG.md](CHANGELOG.md) |
| 部署网关与推送服务 | [docs/guides/deployment.md](docs/guides/deployment.md) |
| 开发一个 HTML 应用 | [docs/guides/app-development.md](docs/guides/app-development.md) |
| 调用原生能力（Bridge） | [docs/guides/bridge-api.md](docs/guides/bridge-api.md) |

## 1. 仓库定位与目录结构

本工程是从原 `WebBridgeKit` 单体仓库按照 `ADR-0002` 与 `ADR-0006` 拆分出的**独立 Drel 产品工程**。`SuperApp/` 是保留的源码目录名；工程、target、workspace、scheme 与产品名统一使用 Drel：

- **`SuperApp/`**：完整产品宿主源码（首页、收信箱 Inbox、PWA 应用中心、发现页、设置、审批流、展示目录）与资源。
- **`NotificationServiceExtension/`**：独立 APNs 通知扩展（负责 `PushCipher` 对称加密消息与 `drel.push-envelope.v1` X25519 自托管信封的端到端解密及自定义头像处理，零 CocoaPods 依赖）。
- **`DrelUITests/`**：28 个 XCUITest 端到端与 UI 保真度测试套件。
- **官方 API**：`infra/cloudflare/drel-api-proxy/`（Cloudflare Worker，承载 `api.drel.app`）。
- **自托管服务端**：`Server/native/`（Go 二进制，推荐）；`Server/Sources/WebBridgeServer/` 为已废弃的 Swift 旧实现，仅保留给既有部署迁移。
- **`deploy/` & `infra/`**：网关 Nginx 配置与 Cloudflare Worker 边缘代理（`infra/cloudflare/drel-api-proxy/`）。
- **`tools/` & `scripts/`**：应用层发布门禁、真机冒烟、容器安全策略校验与本地三服务管理脚本。

> 底层 SDK 源码（`Sources/`）、框架资源（`Resources/`）、最小模板（`AppTemplate/`）及框架单元测试（`Tests/`）位于并列开源仓库 [`WebBridgeKit-Framework`](../WebBridgeKit-Framework) 中。

## 2. 环境准备与联调构建

默认约定将 `WebBridgeKit-Framework` 与 `Drel` 并列放置在同一父目录下（可通过环境变量 `WBK_FRAMEWORK_PATH` 自定义底层框架路径）。两个仓库均为 MIT 开源，首次使用先并列克隆：

```bash
# 0. 并列克隆两个仓库（框架缺失时工程无法生成，没有预编译回退）
git clone https://github.com/dyyz1993/WebBridgeKit-Framework.git
git clone https://github.com/dyyz1993/Drel.git
cd Drel

# 1. 生成 Xcode 工程并安装依赖（自动关联 ../WebBridgeKit-Framework）
xcodegen generate
pod install

# 2.（可选）启动本地联调用的旧版 Swift 测试服务（:8080 / :8081 / :8083）
#    仅用于本地协议联调；生产自托管请使用 Server/native/（见 Server/README.md）
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

### 装到你自己的 iPhone 上

- **模拟器**：上面的步骤开箱即用，不需要任何开发者证书。
- **真机**：需要你自己的付费 Apple Developer 账号。`project.yml` 默认使用作者的 Team 与 Bundle ID（`com.webbridgekit.superapp`），请把 `DEVELOPMENT_TEAM` 与 Bundle ID 改成你自己的，再用自动签名运行；通知扩展 `NotificationServiceExtension` 的 Bundle ID 与 App Group 也要一并改。
- **只想使用成品**：无需自行构建，请通过官网 [drel.app](https://drel.app) 获取已发布版本。

## 3. 应用层启动注入配置

在 `SuperApp/Sources/AppDelegate.swift` 启动阶段，应用层显式向底层框架注入产品命名空间与策略：

- `PushCipher.configure(appGroup: "group.com.webbridgekit.superapp", keychainService: "com.webbridgekit.superapp.push-crypto")`
- `SelfHostedPushCrypto.configure(appGroup: "group.com.webbridgekit.superapp")`
- `HTMLAppGatewayDefaults.configureOfficial(...)`
- `WebBridgeHostCapabilityPolicy.containerOnlyOverride`（跟随应用层 `#if DREL_CONTAINER_ONLY` 编译宏）

## 4. 开发规范与文档

完整的文档地图见 [`docs/README.md`](docs/README.md)。核心入口：

- [应用开发指南](docs/guides/app-development.md) — 从一个普通网页到可安装、可离线、可被推送拉起的完整路径
- [Bridge API 参考](docs/guides/bridge-api.md) — 原生能力的调用契约、授权判定链与降级规范
- [部署手册](docs/guides/deployment.md) — 网关与推送的一体化部署与解耦独立部署
- [协作与排障 SOP](docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md) — 应用层遇到框架问题的标准处理流程

## 5. 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。开源许可为 [MIT](LICENSE)。

## 6. 官网与体验站点

官网位于 `docs/site/`（Cloudflare Pages）。本地预览与校验：

```bash
bash tools/build-drel-site.sh                    # 构建到 build/drel-site-staging
python3 tools/verify-drel-site.py                # 校验链接、demo 完整性与资源哈希
python3 tools/serve-drel-site.py --port 8788     # 本地预览（含 _headers 规则）
```

可体验的演示站点说明见 [docs/site/README.md](docs/site/README.md)。
