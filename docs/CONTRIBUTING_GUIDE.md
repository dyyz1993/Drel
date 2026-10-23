# Drel 贡献规范与 CI 门禁

本仓库把"该做什么"固化成了**可执行的检查**，而不是靠人记住。每一个规范都对应一个脚本，脚本都接在 CI 和发布门禁里。

---

## 1. 门禁全景

```
┌──────────────────────────────────────────────────────────┐
│  PR 触发（push / pull_request）                          │
│                                                          │
│  swiftlint ─ build ─┬─ design-lint                      │
│                      ├─ release-purity                   │
│                      ├─ repo-conventions ★ 新增          │
│                      ├─ smoke-tests / ui-fidelity        │
│                      └─ server-linux                     │
└──────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────┐
│  发布门禁 tools/run-release-gate.sh                      │
│  服务 → 交付边界 → 发布记录 → 发布身份 → 文档链接 →       │
│  仓库卫生 → SwiftLint → 设计 lint → 构建 → 崩溃扫描 →    │
│  归档 → 版本身份 → 无测试 HTML → 无 DEBUG 代码 → ...     │
└──────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────┐
│  发版 tools/publish-drel-testflight.sh                    │
│  归档前强制：发布身份 + 发布记录 + 仓库卫生              │
└──────────────────────────────────────────────────────────┘
```

---

## 2. 规范 → 检查 → 强制点

| 规范 | 检查脚本 | 强制点 | 失败后果 |
|---|---|---|---|
| 文档链接不能断 | `verify-docs-links.py` | CI + 发布门禁 | PR 变红 / 门禁失败 |
| CHANGELOG 与发布材料一致 | `verify-release-notes.py` | CI + 发布门禁 + 发版 | PR 变红 / 拒绝发版 |
| 版本身份可追溯 | `verify-release-identity.py` | 发布门禁 + 发版 | 拒绝发版 |
| 仓库无大文件、无凭证 | `verify-repo-hygiene.py` | CI + 发布门禁 + 发版 | PR 变红 / 拒绝发版 |
| 官网链接、demo、资源哈希正确 | `verify-drel-site.py` | CI + 发版 | PR 变红 |
| 交付边界不被破坏 | `verify-deliverable-boundaries.sh` | 发布门禁 | 门禁失败 |
| Release 不含 Debug 代码 | `verify-release-no-debug.sh` | CI + 发布门禁 | PR 变红 |
| 崩溃为 0 | `scan-crash-logs.sh` | CI + 发布门禁 | 门禁失败 |
| 业务警告为 0 | `swiftlint` | CI + 发布门禁 | PR 变红 |

---

## 3. 版本日志规范

### CHANGELOG.md

每条变更**必须**带三段，缺一不可：

```markdown
- 描述变更本身。 — Scope: `App`, `Gateway` — Verified: `simulator` — Evidence:
  [release/1.5.0/verification.md](release/1.5.0/verification.md)
```

| 字段 | 取值 | 说明 |
|---|---|---|
| `Scope:` | `App` `Gateway` `Push` `Bridge` `Website` `Server` | 影响面 |
| `Verified:` | `physical-device` `simulator` `server-test` `manual` `none` | 验证强度 |
| `Evidence:` | 仓库内文件链接 | 证据位置 |

**`Security` 和 `Bridge` 条目必须有真实存在的证据文件**（`verify-release-notes.py` 强制）。

`Known issues` 小节里的条目是待办，不适用这个契约。

### docs/release/<version>/

```
docs/release/1.5.0/
├── RELEASE-NOTES.md      ← 对外文案（中英双语）
├── app-review-notes.md  ← App Review 提交用
├── verification.md      ← 真机/模拟器验证记录
├── owner-decisions.md   ← 产品决策（可选）
└── artifacts/           ← 证据截图（可选）
```

`RELEASE-NOTES.md` 和 `app-review-notes.md` 是**必需**的。

### 对外文案的硬约束

`verify-release-identity.py` 会扫描 `RELEASE-NOTES.md`，**不允许宣称 Store 宿主策略没有的能力**：

| 不可宣称 | 英文 | 中文 |
|---|---|---|
| 相机扫码 | camera scanning | 相机、扫码 |
| 相册 | photo library | 相册 |
| 蓝牙 | bluetooth | 蓝牙 |
| 麦克风 | microphone | 麦克风 |
| 定位 | location | 定位 |
| 通讯录 | contacts | 通讯录 |
| 通用 JS Bridge | javascript-to-native bridge | 原生 bridge、原生桥 |

允许宣称的动作只有 4 个：`haptic` `vibrate` `share` `fullscreen`。

> 检查能识别中英文，并会跳过"Restrained capability scope"这类**限制性**表述。

---

## 4. 仓库卫生规范

| 规则 | 阈值 | 原因 |
|---|---|---|
| 单文件大小 | ≤ 20 MB | 一次 515MB 录屏差点进库；GitHub 硬拒 >100MB |
| 未跟踪大文件 | ≤ 50 MB | 提醒先加 `.gitignore` |
| 凭证 | 0 | APNs `.p8`、admin key 进历史 = 永久泄漏 |

被检查的凭证形态：APNs 私钥头、`AuthKey_*.p8`、Apple 私钥体、赋值的 `api_key`/`secret`/`token`。

**白名单**：文档里的 `YOUR_KEY`、`example.com`、`changeme-admin-api-key`、路径变量名等不会误报。

---

## 5. 文档规范

| 规则 | 强制点 |
|---|---|
| 仓库内 Markdown 内部链接必须可达 | `verify-docs-links.py` |
| 官网所有链接必须可达 | `verify-drel-site.py` |
| 每个 demo 目录必须有：落地页 + manifest + 应用页 | `verify-drel-site.py` |
| 发布离线包时，资源清单的 SHA-256 必须与实际字节一致 | `verify-drel-site.py` |
| `docs/README.md` 是文档地图，新增文档要挂上去 | 人工评审 |

**新增 demo 站点的完整清单**：

```
/test/<name>/
├── index.html           ← 落地页（讲解 + 产物链接 + 打开方式）
├── v1/index.html        ← 应用本体
├── manifest.webmanifest
├── package.json         ← 资源清单（离线包才有）
├── gateway-manifest.json← 待签名父清单（离线包才有）
└── assets/              ← 图标（不进摘要）
```

并在 `_headers` 补 MIME 与缓存规则。

---

## 6. 发版流程

### 四步显式流程

发版拆成四个**必须显式调用**的步骤，任何一步都不会被其他步骤自动触发：

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ 1. tag   │ → │ 2. test  │ → │ 3.confirm │ → │ 4.publish│
└──────────┘   └──────────┘   └──────────┘   └──────────┘
 打注解 tag      跑全部门禁       记录审批人       推 tag
                  写测试报告        写进报告        可选上传
```

准备阶段（发版前做一次）：

```bash
# 1. 改版本号（project.yml）
#    MARKETING_VERSION + CURRENT_PROJECT_VERSION 同时更新 App 与 NSE

# 2. 写 CHANGELOG 条目 + docs/release/<version>/ 材料

# 3. 提交（提交信息遵循 Conventional Commits）
git add -A && git commit -m "chore(build): bump 1.5.0 (99) — <reason> to TestFlight"
```

发版阶段：

```bash
# 1. 打 tag（校验工作树干净、版本号与 project.yml 一致、CHANGELOG 有该版本）
bash tools/release-drel.sh tag 1.5.0 99

# 2. 跑全部门禁并生成报告（此时不发布任何东西）
bash tools/release-drel.sh test 1.5.0 99
#    报告：build/reports/release-1.5.0-99.md
#    需要跑后端契约测试时加上：
#    DREL_CONTRACT_BASE_URL=http://127.0.0.1:8080 bash tools/release-drel.sh test 1.5.0 99

# 3. 人工确认（把审批人写进报告）
bash tools/release-drel.sh confirm 1.5.0 99 --approved-by "your name"

# 4. 发布
bash tools/release-drel.sh publish 1.5.0 99
#    连带上传 TestFlight：
#    DREL_PUBLISH_TESTFLIGHT=1 bash tools/release-drel.sh publish 1.5.0 99
```

**保护机制**：

- `tag` 拒绝脏工作树、版本号与 `project.yml` 不一致、CHANGELOG 缺该版本
- `test` 任何一个门禁失败就整体失败
- `publish` 拒绝没有 tag、报告不是 PASS、或没有 recorded approval 的发布

**门禁清单**（`test` 步骤）：

| 门禁 | 脚本 |
|---|---|
| 发布记录一致性 | `verify-release-notes.py` |
| 文档链接 | `verify-docs-links.py` |
| 仓库卫生 | `verify-repo-hygiene.py` |
| 设计系统 lint | `ci-lint.sh` |
| Go 服务端测试 | `go test ./...` |
| CF Worker 测试 | `npm test` |
| 官网链接与资源 | `build-drel-site.sh` + `verify-drel-site.py` |
| 图表新鲜度 | `build-drel-diagrams.sh --check` |
| 后端契约（可选） | `verify-drel-backend-contract.sh` |

### 后端契约测试

同一套 curl 用例可以跑在任意后端上，用来证明实现之间兼容：

```bash
bash tools/verify-drel-backend-contract.sh \
  --base http://127.0.0.1:8080 \
  --admin-key "$ADMIN_KEY" \
  --write-report build/reports/contract-go.md
```

它覆盖网关发现、清单录入、**OpenSSL 独立验签**、列表、鉴权、推送路由和删除。
Go 二进制、Swift 服务端、CF Worker 三者跑出的报告逐行一致。

### 门禁会在这些点拦住你

- **改了版本号但没写 CHANGELOG** → `verify-release-notes.py` 失败
- **改了 CHANGELOG 但没建 release 目录** → 失败
- **工作树没提交就发版** → `verify-release-identity.py` 失败
- **对外文案宣称了没有的能力** → 失败
- **提交了大文件或凭证** → 失败

---

## 7. 建议的 GitHub 分支保护

仓库转 Public 后，在 `Settings → Branches → main` 开启：

**Required status checks**（勾选这 5 个）：

```
📋 Repository Conventions
🔒 Release Purity
🎨 Design System Lint
SwiftLint
Drel Smoke Tests
```

**Rules**：
- Require a pull request before merging
- Require branches to be up to date
- Do not allow bypassing the above settings

这样即使有人直接 push 到 main，规范也拦得住。

---

## 相关文档

- [AGENTS.md](../AGENTS.md) — 仓库总规范与已知陷阱
- [开发与协作指南](DEVELOPMENT_AND_COLLABORATION_GUIDE.md) — App/Framework 协作 SOP
- [CHANGELOG.md](../CHANGELOG.md) — 版本变更记录
