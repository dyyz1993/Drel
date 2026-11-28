# Drel 文档地图

Drel 的文档按"读者要做什么"组织，而不是按代码目录组织。从这里找到你的路径。

## English summary

This page is Drel's documentation map. Start with the
[Push API](https://drel.app/docs/push/) to send notifications; use the
[deployment guide](guides/deployment.md) and
[Self-hosted overview](https://drel.app/self-hosted/) for private deployment.
Build apps with the [app development guide](guides/app-development.md), then
use the [Bridge API reference](guides/bridge-api.md). The reader-specific
tables below point to the remaining contracts and workflows.

---

## 面向使用者

| 你要做的事 | 文档 |
|---|---|
| 发送一条推送 | [官网 Push API](https://drel.app/docs/push/) |
| 从 Bark 迁移 | [Bark 兼容与迁移指南](https://drel.app/compare/bark/) · [中文版](https://drel.app/zh/compare/bark/) |
| 私有化部署（推送 / 网关 / 两者） | [部署手册](guides/deployment.md) · [官网选项页](https://drel.app/self-hosted/) |
| 准备一次部署（生成密钥 + 配置文件） | `bash tools/prepare-drel-deployment.sh <gateway\|relay\|both> --domain <host>` |
| 部署到自己的服务器（打包二进制 + 反代配置） | `bash tools/build-drel-selfhosted-package.sh --arch arm64 --domain <host>` |
| 三个后端怎么共存、怎么切流 | [服务端部署方案](guides/server-deployment.md) |
| 验证任意后端与官方实现兼容 | `bash tools/verify-drel-backend-contract.sh --base <url> --admin-key <key>` |
| 了解版本兼容性 | [官网 Versions](https://drel.app/docs/versions/) · [CHANGELOG](../CHANGELOG.md) |

---

## 面向应用开发者

这是给"我要在 Drel 里跑一个网页应用"的人看的。

| 章节 | 内容 |
|---|---|
| [应用开发指南](guides/app-development.md) | **主入口**。四层递进：普通网页 → PWA 应用 → 强离线包 → 原生能力集成 |
| [Bridge API 参考](guides/bridge-api.md) | 原生能力的调用契约、六道授权判定链、TypeScript 定义与 Mock 调试 |
| [PWA / Bridge 网页开发指南](pwa-bridge-guide.md) | 受保护能力的完整清单与授权面板行为（底层 SDK 视角） |
| [WebBridgeKit PWA Developer Guide](guides/pwa-developer-guide.md) | 网关签名的应用清单与 Bridge 门面用法 |
| [离线 HTML 应用整合指南](guides/offline-html-app-guide.md) | 打包 → 部署 → 录入 → 手机出现的完整管线 |
| [自部署网关导入](guides/self-hosted-gateway-import.md) | 二维码/粘贴导入网关与信任边界 |

### 契约文档（`api/`）

| 文档 | 用途 |
|---|---|
| [gateway-v1](api/gateway-v1.md) | 网关配置与清单签名契约 |
| [html-app-onboarding](api/html-app-onboarding.md) | HTML 应用注册总览 |
| [drel-web-app-manifest-profile](api/drel-web-app-manifest-profile.md) | Web App Manifest 字段规范 |
| [offline-package-v1](api/offline-package-v1.md) | 强离线资源清单格式 |
| [push-v2](api/push-v2.md) | 推送接口契约 |
| [drel-selfhosted-push](api/drel-selfhosted-push.md) | 自托管推送协议 |
| [drel-managed-encrypted-push](api/drel-managed-encrypted-push.md) | 托管加密推送信封 |
| [message-types-v1](api/message-types-v1.md) | 消息类型 |
| [approval-v1](api/approval-v1.md) | 审批流 |
| [drel-app-link](api/drel-app-link.md) | 应用深链规范 |
| [drel-container-only-launch](api/drel-container-only-launch.md) | 纯容器启动约束 |
| [drel-offline-template](api/drel-offline-template.md) | 离线包数据注入模板 |

---

## 面向运维与部署

| 章节 | 内容 |
|---|---|
| [部署手册](guides/deployment.md) | **主入口**。网关与推送的一体化部署与解耦独立部署 |
| [Server/README](../Server/README.md) | 推送服务端自身的部署细节（Docker / systemd / Cloudflare Tunnel） |
| [官网 Self-host](https://drel.app/self-hosted/) | 面向用户的自托管信任边界说明 |

---

## 面向贡献者

| 章节 | 内容 |
|---|---|
| [AGENTS.md](../AGENTS.md) | 仓库开发规范、验证脚本、已知陷阱（**动手前必读**） |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | 协作流程 |
| [贡献规范与 CI 门禁](CONTRIBUTING_GUIDE.md) | **规范 → 检查脚本 → 强制点** 的完整对照表，以及发版流程 |
| [CHANGELOG.md](../CHANGELOG.md) | 每个版本的变更与验证证据 |
| [docs/release/](release/) | 每个版本的发布材料（对外文案、审核说明、验证记录） |
| [docs/adr/](adr/) | 架构决策记录 |
| （设计计划保留在维护者的内部记录中） | — |
| [docs/verification/](verification/) | 模块可用性验证报告 |
| [docs/testing/results/](testing/results/) | 回归测试与可视化证据 |
| [docs/architecture/](architecture/) | 协议与架构说明 |

---

## 面向开发者的入口顺序

首页的用户路线以 **skill 为主轴**：安装 → 交给 Agent → 自己试 → 私有化部署。
文档承担快速查阅、在线 playground 调试和私有化部署的逐步操作。

| 想要 | 走哪条路 |
|---|---|
| 让 AI 帮我做 | `npx skills add dyyz1993/Drel --skill drel-app-development` |
| 自己发一条试试 | 官网 `/docs/push/` 的 playground |
| 查参数契约 | 官网 `/docs/push/`（每个字段标注来源与版本） |
| 私有化部署 | 仓库 `docs/guides/deployment.md`，先跑 `tools/prepare-drel-deployment.sh` |

## 体验站点

线上可动手体验的演示（构建与预览见 [docs/site/README.md](site/README.md)）：

| 路径 | 验证什么 |
|---|---|
| `/test/offline/` | 强离线包：安装、校验、断网启动 |
| `/test/offline-network/` | 离线包 + 实时网络数据的降级 |
| `/test/actions/` | Manifest v2 声明式原生操作（触感/震动/分享/全屏） |
| `/test/template/` | 可复用的应用骨架与打包模板 |
| `/launch/` | 桌面入口：添加到主屏幕并交接到 Drel |

## 架构图

官网文档内嵌 6 张图。源文件是 `docs/diagrams/*.mmd`（Mermaid 文本，可 review、可 diff），由 `tools/build-drel-diagrams.sh` 渲染成 SVG：

| 图 | 说明 | 位置 |
|---|---|---|
| `system-architecture.svg` | 三个部件的关系：应用 / 网关 / 推送服务 | `/docs/` |
| `push-sequence.svg` | 一条推送从脚本到手机的完整时序 | `/docs/push/` |
| `signing-chain.svg` | 清单如何被签名、验证与固定 | `/docs/app/` |
| `offline-install.svg` | 离线包的下载、逐文件校验与原子激活 | `/docs/offline/` |
| `deployment-topology.svg` | 一体化部署与解耦独立部署的对比 | `/self-hosted/` |
| `key-trust-sequence.svg` | 密钥与信任时序：每个私钥住在哪一端 | `/self-hosted/` |

图中的每条关系都对照过实现（例如 APNs 只走 HTTP/2：Swift relay 用 `curl --http2`，Go relay 用 `ForceAttemptHTTP2`；离线安装在 staging 目录逐文件校验后才原子激活）。改动实现后编辑对应的 `.mmd` 源文件，再运行 `bash tools/build-drel-diagrams.sh`；CI 会用 `--check` 拦住忘了重新渲染的提交。

---

## 文档维护约定

- **真相源在仓库**：`docs/` 与 `CHANGELOG.md` 是唯一真相源，官网 `docs/site/` 是它的呈现。
- **改动要同步**：改了契约就同时更新 `api/` 文档与官网对应页面。
- **发布要留证**：`CHANGELOG.md` 的每条变更都要带 Scope / Verified / Evidence 三段，`tools/verify-release-notes.py` 会在发布门禁里强制检查。
- **链接要有效**：`tools/verify-drel-site.py` 会遍历全站链接、校验 demo 完整性与资源哈希。
