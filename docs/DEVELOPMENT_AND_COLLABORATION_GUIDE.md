# Drel 开发与协作指南

Drel 与底层框架 `WebBridgeKit-Framework` 的协作约定，以及应用层遇到框架问题时的标准排查流程。

> 本文取代了早期引用但从未存在于本仓库的 `DEVELOPMENT_AND_COLLABORATION_GUIDE.md`。

---

## 1. 仓库分工

| 仓库 | 归属 | 公开性 |
|---|---|---|
| `Drel`（本仓库） | iOS 产品、通知扩展、UI 测试、官网、技能、服务端 | **公开（MIT）** |
| `WebBridgeKit-Framework`（同级） | 通用运行时 SDK、协议、缓存、消息、Bridge 引擎 | **闭源** |

Drel 通过 CocoaPods 以预编译 `WebBridgeKit.xcframework` 消费框架产物。

### 本地开发时的框架路径

`Podfile` 默认从 `../WebBridgeKit-Framework` 取源码：

```ruby
wbk_path = ENV.fetch('WBK_FRAMEWORK_PATH', '../WebBridgeKit-Framework')
pod 'WebBridgeKit', :path => wbk_path
```

外部贡献者没有该仓库时，依赖回退到预编译的 xcframework（见 §2）。

---

## 2. 两种依赖模式

| 模式 | 触发条件 | 用途 |
|---|---|---|
| **源码模式** | `../WebBridgeKit-Framework` 存在 | 框架开发者同步改 SDK 与宿主 |
| **二进制模式** | 该目录不存在 | 外部贡献者、CI、只改 App 的场景 |

`pod install` 会自动选择，不需要手动切换。切换模式后建议：

```bash
rm -rf Pods/ Podfile.lock
pod install
```

---

## 3. 改动归属：先证明契约，再补产品

Drel 有三个交付面，职责不能混：

| 交付面 | 拥有什么 |
|---|---|
| `Sources/`（在框架仓库） | 通用运行时模型、协议、服务、安全、路由、缓存、消息、Bridge 行为 |
| `SuperApp/`（本仓库） | 终端用户旅程、产品文案、导航、收件箱、应用中心、设置、官方托管/自托管体验 |
| `Server/` + `docs/api/` | 网关、推送、审批、回调契约 |

**规则**：新增可复用能力时，先在框架或服务端证明契约，再在 `SuperApp/` 完成产品旅程。AppTemplate 只在公开 API 稳定后更新，且只放最小集成示例。

**验证**：

```bash
bash tools/verify-deliverable-boundaries.sh
```

---

## 4. 应用层遇到底层框架问题：标准 SOP

### 步骤 1：先确认是"影子源码"还是"真 bug"

**XcodeGen 只编译 `project.yml` 里 `sources:` glob 匹配到的文件。** 匹配不到任何 target 的文件会被静默忽略——零警告、零错误。

```bash
grep '<File>.swift in Sources' WebBridgeKit.xcodeproj/project.pbxproj
# 0 匹配 = 你的改动编译进了虚无
```

**已知的影子陷阱**：

| 陷阱 | 真相源 | 不要动 |
|---|---|---|
| 通知服务扩展 | 根目录 `NotificationServiceExtension/` | `SuperApp/NotificationServiceExtension/`（已删除，别复活） |
| 权限文件 | 根目录与 `SuperApp/` 的副本必须一致 | 任一单边修改 |

### 步骤 2：验证"发布出去的二进制"，而不是源码

App Store / TestFlight 的 IPA 是 FairPlay 加密的，`strings` 看不到东西。用未加密的归档产物：

```bash
strings -a /tmp/wbk-archive/.../PlugIns/*.appex/* | grep <marker>
```

**marker 必须 ≥16 字节。** Swift 小字符串优化会把 ≤15 字节的字面量编码成立即数、不落数据段，`strings` 永远看不到。这时改查 dSYM 符号：

```bash
strings -a <dSYM>/.../DWARF/<name> | grep <funcName>
```

### 步骤 3：警惕"多级回退掩盖死代码"

服务端历史、应用组 plist 这类多级回退，会让某一层坏掉好几天都不被发现。**改了哪一层，就直接验证那一层的产物**，不要只看最终的用户可见结果。

### 步骤 4：核对服务端版本

legacy backend 是手工 rsync 部署的（`/root/WebBridgeKit` 无 git remote），"服务端没更新"曾多次造成假差异排查。

```bash
curl -k https://gateway.example.invalid:8443/health | grep version
```

**客户端修复与服务端修复是两条发布线**：分别核对 `/health` 版本和 TestFlight 构建时间。

---

## 5. 代码质量门禁

```bash
swiftlint --quiet                        # 业务代码零警告
bash tools/ci-lint.sh                    # 设计系统 lint
bash tools/verify-deliverable-boundaries.sh
bash tools/verify-release-notes.py       # CHANGELOG 与发布材料一致性
bash tools/verify-drel-site.py           # 官网链接、demo 完整性、资源哈希
```

**业务代码警告必须为 0。** 工具链（CocoaPods、SPM、Xcode 本身）的警告可以接受。

**崩溃必须为 0**：

```bash
bash scripts/scan-crash-logs.sh --json   # 期望 "total": 0
```

---

## 6. 发布前的完整门禁

```bash
bash tools/run-release-gate.sh
```

它会依次跑：服务启动 → 交付边界 → **发布材料一致性** → SwiftLint → 设计 lint → Debug 构建 → 崩溃扫描 → Release 归档 → 归档版本身份 → 无测试 HTML → Release 无 Debug 代码 → 应用层回归 → 各项策略校验。

**每个发版都要有**：

1. `CHANGELOG.md` 的条目（带 Scope / Verified / Evidence）
2. `docs/release/<version>/` 的发布材料
3. `docs/testing/results/` 的验证证据

`tools/verify-release-notes.py` 会在门禁里强制检查这三点。

---

## 7. 提交规范

- 从 `main` 切分支；有并行会话时用独立 worktree。
- Conventional Commits：`fix(app): ...`、`feat(v2): ...`、`docs(release): ...`。
- 提交要聚焦，并在 PR 里记录检查结果。
- 向 `main` 提 PR，等待维护者评审。

**每个 TestFlight 上传必须在同一次 push 里带上** `chore(build): bump <marketing> (<build>) — <reason> to TestFlight` 提交，且同时更新 App 与 NSE 的 `CURRENT_PROJECT_VERSION`。见 [ADR-0005](adr/0005-app-marketing-version-policy.md)。

---

## 8. 本地服务

```bash
bash scripts/services.sh start
bash scripts/services.sh verify
bash scripts/services.sh stop
```

| 服务 | 端口 | 用途 |
|---|---|---|
| 后端（Swift） | 8080 | 网关、推送、命令路由 |
| 测试 HTTP | 8081 | 缓存测试静态资源 |
| 原型 | 8083 | HTML 原型对比 |

**物理 iPhone 用公网 legacy backend 地址**（手机不能可靠访问 agent 本机的 localhost）；**模拟器与 CI 用本地端口**（测试依赖确定性夹具）。

---

## 相关文档

- [AGENTS.md](../AGENTS.md) — 仓库总规范与已知陷阱
- [文档地图](README.md) — 全部文档入口
- [CHANGELOG](../CHANGELOG.md) — 版本变更与验证证据
- [发布材料](release/) — 每个版本的对外文案、审核说明、验证记录
