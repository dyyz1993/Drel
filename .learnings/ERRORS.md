# Errors

Command failures, API errors, and unexpected behavior captured during development.

**Areas**: frontend | backend | infra | tests | docs | config
**Statuses**: pending | in_progress | resolved | wont_fix | promoted | promoted_to_skill

## Status Definitions

| Status | Meaning |
|--------|---------|
| `pending` | Not yet addressed |
| `in_progress` | Actively being worked on |
| `resolved` | Issue fixed (add Resolution block) |
| `wont_fix` | Decided not to address (reason in Resolution) |
| `promoted` | Elevated to CLAUDE.md, AGENTS.md, or copilot-instructions.md |
| `promoted_to_skill` | Extracted as a reusable skill |

Entry format: see the self-improvement skill's "Error Entry" section. IDs use `ERR-YYYYMMDD-XXX`.

---

## [ERR-20261021-001] tests

**Logged**: 2026-10-21
**Symptom**: 定位类 UI 测试在授权链路全通过后仍失败，页面结果区显示
`定位失败：Failed to get location: 未能完成操作。（kCLErrorDomain 错误 0。）`。
同一套测试此前全绿、代码无改动，复跑仍失败，易误判为授权/面板回归。

**Root Cause**: 模拟器的 `simctl location` 预设坐标会随时间/设备重启失效，
CLLocationManager 拿不到 fix 返回 kCLErrorDomain code 0（定位失败），与
权限授予状态无关。Drel-Flow-Verify 模拟器上两轮复现，重设坐标后立即恢复全绿。

**Resolution**: 定位相关 UI 测试复跑前先执行
`xcrun simctl location <udid> set 31.2304,121.4737`（必要时再
`xcrun simctl privacy <udid> grant location com.webbridgekit.superapp`）。
已写入 docs/testing/results/drel-permission-flow-101/verification.md 环境备注。

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable (模拟器行为由 Xcode/CoreSimulator 决定，变化慢)
- Authority: 本机实测两轮复现 + 修复验证; Owner: Drel 客户端
- Revalidation: 复跑定位 UI 测试出现 kCLErrorDomain 0 即触发重设; 不可用来源无影响
- Validation: verified; Last-Validated: 2026-10-21; Evidence: 重设坐标后 17/17 全绿两轮
- Disposition: retain; Application: 已应用于本轮测试流程

## [ERR-20261021-002] frontend

**Logged**: 2026-10-21
**Symptom**: 权限能力卡的「始终允许」胶囊芯片用 UILabel 实现（backgroundColor +
cornerRadius，放入 UIStackView），UI 测试断言 AX 树上存在且 frame 正常
（50×13pt），但截图像素完全不渲染，视觉上空白。同样的 AX 有/像素无不符
无法用常规布局手段排查。

**Root Cause**: 未完全定界（UILabel 在该 stack 组合下的渲染异常）。
改用 disabled UIButton（setTitle + contentEdgeInsets + backgroundColor）后
同一位置渲染正常且稳定。

**Resolution**: 带背景色的内联芯片/徽章一律用 disabled UIButton 实现，
不用 UILabel + backgroundColor。已在
PWAPermissionCenterViewController.makeCapabilityCard 落地。

**Status**: resolved

**Context Maintenance**
- Decay-Type: unknown
- Decay-Rate: durable (UIKit 渲染行为，系统级)
- Authority: 本机实测（AX frame 存在 + 截图像素空白 → UIButton 修复）; Owner: Drel 客户端
- Revalidation: 未来若 iOS 大版本升级可复验 UILabel 行为; 不可用来源无影响
- Validation: verified; Last-Validated: 2026-10-21; Evidence: chip 截图修复前后对比
- Disposition: retain; Application: applied

## [ERR-20261022-001] frontend

**Logged**: 2026-10-22
**Symptom**: 用户实测：App 退出重进后，之前选的「始终允许」失效，每次调用都重新弹授权面板。

**Root Cause**: 两处叠加。
1. `AppDelegate.registerBridgePermissionFixtureIfRequested()` 在每次启动时无条件执行
   `permissionLedger.revokeAll(appID: fixtureAppID)`——本意是“测试前清干净”，
   实际把用户的持久授权在每次冷启动时删掉。
2. 框架 `HTMLAppPermissionLedger.syncGrants` 在 manifest 重注册时，把“授权 scope
   与签名声明 scope 不一致”的记录判为过期清掉；而 scope 是用户在面板上选的，
   不是声明的默认值。

**Resolution**: 1 改为仅 `--reset-permission-grants` 显式传入时清（UI 测试用）；
2 去掉 scope 相等条件，只校验 actionIdentity/capability/origin。
新增 `test05AlwaysGrantSurvivesAppRelaunch` 锁死；其余用例改用显式
`--reset-permission-grants` 做测试隔离（避免修复后用例间状态互相污染）。

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 用户实测反馈 + 测试复现修复; Owner: Drel 客户端 + 框架
- Revalidation: 每次涉及授权账本/启动种子的改动
- Validation: verified; Last-Validated: 2026-10-22; Evidence: 18/18 回归全绿
- Disposition: retain; Application: applied

## [ERR-20261022-002] frontend

**Logged**: 2026-10-22
**Symptom**: 用户实测：点「分享演示内容」拉起的 iOS 分享面板，顶部标题显示
`example.com`（网页里硬编码的占位 URL），不是应用名；logo 也没有。

**Root Cause**:
1. `WebShareHandler.presentShare` 直接把 `[text, url]` 交给
   UIActivityViewController，iOS 自动把 URL item 的 host 当预览标题。
2. 演示页传了 `https://example.com/pwa-v2-demo` 和第三方图床 iconURL；
   框架的同源限制把第三方图标拦掉 → 图标为 nil。

**Resolution**: 提供显式 `SharePreviewItemSource`（UIActivityItemSource +
LPLinkMetadata）：标题取当前注册应用名、副标题取网页文案、缩略图取应用自己的
manifest 图标（仅 https 同源）。演示页改为传真实应用名与 `window.location.href`。
截图：docs/testing/results/drel-permission-flow-101/screenshots/share-panel-app-name.png

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 用户实测反馈 + 修复后截图验证; Owner: 框架 + Drel 演示页
- Revalidation: 涉及分享/预览的改动
- Validation: verified; Last-Validated: 2026-10-22; Evidence: 面板标题=原生能力演示
- Disposition: retain; Application: applied

## [ERR-20261022-003] frontend

**Logged**: 2026-10-22
**Symptom**: 用户实测：设置 → 网页授权管理页，点授权卡片（不是点「撤销」按钮）
授权就消失了，没有任何二次确认。

**Root Cause**: 两个缺陷叠加。
1. `WebOriginGrantsView.revoke()` 直接执行撤销并 reload，没有确认面板
   （权限中心页有确认，这个页面漏了）。
2. SwiftUI List 行内 `Button("撤销")` 的默认热区横向铺满整行，点卡片空白处
   也触发撤销。

**Resolution**: 撤销前弹 `.alert` 二次确认（取消保留授权）；按钮加
`.buttonStyle(.plain) + .contentShape(Rectangle())` 收紧热区。
顺带过滤掉 `.once` 授权（一次性事实不该出现在授权管理页）。

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 用户实测反馈; Owner: Drel 设置页
- Revalidation: 涉及授权管理/撤销入口的改动
- Validation: verified; Last-Validated: 2026-10-22; Evidence: 18/18 回归全绿 + 装机待用户验收
- Disposition: retain; Application: applied

## [ERR-20261022-004] frontend

**Logged**: 2026-10-22
**Symptom**: 用户实测：从授权面板点「查看与管理授权」跳进权限与能力页（全屏），
左上角没有返回按钮，返回不了。

**Root Cause**: 该页 `viewDidLoad` 只处理了「push 进栈」的场景
（`setNavigationBarHidden(false)` 恢复导航栏）。快捷入口是模态 present 一个
UINavigationController，本页成为导航根页面，没有可返回的上级 → 无返回入口。
同型问题 2026-08-23 已在 push 路径修过一次（沉浸式浏览器），这次是模态路径复发。

**Resolution**: 模态呈现且本页为导航根页面时，自动装左上角「关闭」按钮
（identifier `pwa-permission.close`），dismiss 整个导航容器。

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 用户实测反馈; Owner: Drel 权限中心
- Revalidation: 新增任何以模态方式呈现权限中心的入口
- Validation: verified; Last-Validated: 2026-10-22; Evidence: test04 强制断言关闭按钮存在并可返回，18/18 全绿
- Disposition: retain; Application: applied

**教训（测试为何漏掉）**: test04 原写法是「如果找到返回按钮就点」——条件式断言，
按钮缺失时测试照样通过。破坏性 UI 缺失必须用强制断言。

## [ERR-20261022-005] frontend

**Logged**: 2026-10-22（同一现象在 ERR-20261022-001 之后再次出现，本条为不同根因）
**Symptom**: 用户实测：选「始终允许」→ 杀掉 App → 重开，授权丢失、仍然弹授权面板。
此前已修过一次（AppDelegate fixture 无条件 revokeAll），但真机仍复现。

**Root Cause（真因，与 001 不同）**: 框架 `HTMLAppRuntime.requestAuthorization`
免询问分支要求 `grant.scope == declaration?.scope`，不匹配时**主动 revoke 刚授予
的授权并返回 denied**。而授权 scope 是用户在面板上选的，声明只是默认值——
商店构建里 action-demo 的定位声明确非 .always，于是用户选的「始终允许」
被判不匹配、立刻撤销 → 表现就是授权活不过重启。

**为何之前的测试没抓到（重要教训）**:
1. 测试用的是 Debug 构建 + `--register-pwa-permission-fixture` 的 localhost
   fixture 应用，其 location 声明为 .always → scope 本来匹配 → 分支不会触发。
2. 真实商店构建（DREL_CONTAINER_ONLY）里 fixture 注册整段不编译，测试覆盖的
   路径与真机完全不是一套代码。
→ 教训：验证「用户可见行为」时，必须确认测试路径与用户实际构建/应用一致，
  否则测试通过只是假绿灯。

**Resolution**: 删掉免询问分支里的 scope 比对与撤销；声明只用于校验能力是否被
声明，不参与 scope 判定（与 syncGrants 的修复口径一致）。

**后续修正（重要，2026-10-22 晚些时候）**: 本条的根因推断**不成立**。
框架校验 `validateActionDeclarations` 强制 grant 类动作（剪贴板/定位）的声明
必须为 `.always`（`.once`/`.appSession` 会让 manifest 注册失败），因此
「声明非 always」在真机上不可能存在，该撤销分支永远不触发。反向验证已证明：
回退此修复，单测照样通过。真实根因见 **ERR-20261022-007**（启动时未同步
gatewayIdentity，导致调用直接被「未配置可信网关」拒绝）。

**Status**: resolved

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 用户实测反馈 + 代码定位; Owner: 框架
- Revalidation: 涉及授权 scope / 声明校验的改动
- Validation: verified; Last-Validated: 2026-10-22; Evidence: 18/18 回归全绿，build 104 待真机验收
- Disposition: retain; Application: applied

## [ERR-20261022-006] config

**Logged**: 2026-10-22
**Symptom**: 发布脚本在上传后报 `UPLOAD_JSON: unbound variable`（103、104 两次），
且轮询一直显示 `processingState=S` 直到超时——但上传其实已成功。

**Root Cause**:
1. 上传块把输出文件变量改名为 UPLOAD_TMP，但结果判断仍引用 UPLOAD_JSON →
   set -u 下未绑定变量中断。
2. 轮询 `grep -oE '[A-Z_]+'` 只取到首字母（VALID → S）。

**Resolution**: 统一用 UPLOAD_TMP；状态解析改为先取整段引号值再 sed 提取。
**Status**: resolved（验证：104 用修复后脚本可判定，且 ASC API 复查为 VALID）

## [ERR-20261022-007] frontend

**Logged**: 2026-10-22
**Symptom**: 用户实测（连续第三次报告同一现象）：选「始终允许」→ 杀掉 App → 重开，
授权不见了、仍然弹授权面板。ERR-20261022-001、ERR-20261022-005 均未解决。

**Root Cause（真因）**: 商店构建（DREL_CONTAINER_ONLY / DREL_V2_MANAGED_ACTIONS_ONLY）
下 `HTMLAppRuntimeCenter.shared.gatewayIdentity` **只在打开应用中心或权限中心时**
才被赋值，冷启动后是空字符串。此时 Bridge 调用受保护能力会在
`WebJavaScriptBridge.permissionSubject` 判空 → 直接返回
`getLocation: 拒绝 (未配置可信网关，不能调用受保护的原生能力)`。
**授权根本没机会落账**，所以不是「授权丢失」，而是「从未写入」。

**Resolution**: App 启动时（AppDelegate）同步已激活网关身份到运行时。

**Status**: resolved（代码已提交；模拟器真机等价验证受网关注册时序阻塞，
待用户真机验收或后续补验）

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: 真机等价构建（Store 编译条件）实测得到错误文本; Owner: Drel AppDelegate
- Revalidation: 涉及网关激活/启动时序的改动
- Validation: verified（根因有明确错误文本为证）; Last-Validated: 2026-10-22;
  Evidence: `getLocation: 拒绝 (未配置可信网关...)`
- Disposition: retain; Application: applied

**教训（为何连续三次修错）**:
1. 测试用的是 Debug 构建 + localhost fixture 应用，与真机（Store 构建 +
   远程 drel.app 注册的 action-demo）不是一套代码路径 —— 测试通过是假绿灯。
2. 未先取得「真机上的实际错误文本」就凭代码推断改了两次。
→ 正确顺序：先用真机等价配置复现并拿到错误输出，再动手改。

## [ERR-20261022-008] framework

**Logged**: 2026-10-22
**Symptom**: 用户实测（关键转折点证据）：“我授权完之后，打开那个应用，权限那里是能看到的。但是，我把 APP 杀掉之后再进来，就看不到了。”

**Root Cause（终局根因，已通过反向单测100%证实）**:
冷启动首页自动触发网关校验刷新 `HTMLAppGatewayOnboardingService.activate(report)`。
该方法使用 `manifest.declares(grant.capability)` 过滤账本保留授权；而 `declares()`
实现仅检查 `capabilities`（V1 数组）！
剪贴板（clipboard）和定位（location）等 V2 受控动作**只声明在 capabilitiesV2 中**，
V1 数组为空。导致每次冷启动网关刷新后，所有 V2 动作的「始终允许」授权被判定为
「已不再声明」，全部被 `permissionLedger.replaceAll(replacementGrants)` 抹掉！
这完美解释了用户的现象：授权后立即可见（写入成功），杀掉重开后网关刷新把它们全清了！

**Verification**:
单元测试 `testGatewayActivationKeepsV2OnlyGrants`：
- 回退修复：`XCTAssertEqual failed: ("0") is not equal to ("2")`（剪贴板和定位全被抹掉，失败证据确凿！）
- 应用修复：`Test Case passed (0.054 seconds)`（2 条记录完整保留，通过！）

**Resolution**: 在 `HTMLAppGatewayOnboarding.swift` 和 `HTMLAppRuntime.swift` 中，
检查授权是否被声明时同时检查 `capabilities`（V1）和 `capabilitiesV2`（V2 动作声明）。

**Status**: resolved

## [ERR-20261028-001] infra

**Logged**: 2026-10-28

**Symptom**: Drel PR #4 的 GitHub Actions job 全部在 1–2 秒内失败，
`steps` 为空，看起来像 workflow 配置错误或 runner 启动失败。

**Root Cause**: GitHub 账号的私有仓库 Actions 额度已用尽，且 Actions budget
为 `$0.00 / $0.00`，状态 `Usage blocked`。Check-run annotation 明确给出：
`The job was not started because recent account payments have failed or your
spending limit needs to be increased.`

**Resolution**: 未完成。需要在 GitHub Billing 添加付款方式并把 Actions budget
调到大于 0，或等待 2,000 分钟额度重置；不能通过改 workflow 或本地测试冒充 CI 绿。

**Status**: in_progress

**Context Maintenance**
- Decay-Type: dependency
- Decay-Rate: fast（额度会按月重置）
- Authority: GitHub Check Runs annotations + Billing 页面实读; Owner: GitHub 账号 dyyz1993
- Revalidation: 重跑前检查 Actions included usage 和 budget 是否仍为 0
- Validation: verified; Last-Validated: 2026-10-28;
  Evidence: build/reports/drel-ci-billing-20261028
- Disposition: retain; Application: blocked on account billing


## [ERR-20261028-002] infra

**Logged**: 2026-10-28

**Symptom**: `tools/check-drel-search-index.sh` 连续两轮退出码 0 但 Google/Baidu
解析结果均为 `{}`（state=unknown），单轮耗时 >5 分钟；`xbrowser chrome-bridge
status` 输出为空。

**Root Cause**: Chrome bridge 服务不可用时 `status` 命令静默失败，脚本把空
probe 当作正常结果渲染，无失败退出码；每步 xbrowser 调用无 shell 级超时，
死等到底层超时。

**Resolution**: status/navigate/evaluate 均加 `timeout`（10s/30s）；bridge
不可用时 exit 2，两引擎 probe 结果为空时 exit 3 并输出 stderr 错误。

**Status**: resolved

**Recurrence**: 2026-10-28 sitemap heartbeat: bridge navigate initially succeeded, but CDP evaluation returned an empty result after timeout even after a bridge restart. Current quota is unknown; the polling attempt must not count as a zero-quota observation.
- Pattern-Key: xbrowser.chrome_bridge.empty_or_timeout
- Recurrence-Count: 2
- Last-Seen: 2026-10-28

**Context Maintenance**
- Decay-Type: dependency
- Decay-Rate: fast（bridge 服务状态随时变化）
- Authority: build/reports/search-index/*.raw.txt 空结果 + status 空输出;
  Owner: xbrowser chrome-bridge
- Revalidation: 每轮 heartbeat 检查 exit code 与 latest.json error 字段
- Validation: verified; Last-Validated: 2026-10-28;
  Evidence: 修改后脚本运行 exit=2 且 1 秒内返回
- Disposition: retain; Application: 所有依赖 chrome-bridge 的检查脚本

## [ERR-20261029-001] infra

**Logged**: 2026-10-29

**Symptom**: `WBK_GATEWAY_URL=https://api.drel.app bash tools/verify-open-gateway.sh`
报 `missing appId com.webbridgekit.fixture.chat`，5 项里 2 项失败（清单 + 按 ID 查询）。

**Root Cause**: 脚本默认 `EXPECTED_APP_ID=com.webbridgekit.fixture.chat`，是为
tx 网关（cloak.xbrowser.dev:5801）与本地 Go 网关设计的固定夹具；api.drel.app
上从未注册过该应用（改动部署前的匿名清单即可佐证），与当日 keybind 部署无关。

**Resolution**: 对 api.drel.app 跑该门时覆盖
`WBK_GATEWAY_APP_ID=<该网关上真实存在的 appId>`（如 dev.vot.workspace），
5/5 全绿。可选改进：脚本在 404 时提示检查目标网关与 EXPECTED_APP_ID 是否匹配。

**Metadata**
- Pattern-Key: drel.verify.open-gateway-target-mismatch
- Recurrence-Count: 1
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29

## [ERR-20261030-001] release

**Logged**: 2026-10-30

**Symptom**: `publish-drel-testflight.sh 119` 在导出阶段失败：
`Signing certificate "Apple Distribution…" serial C4DC782A… is not valid for
code signing`（伴生 `No Accounts`），前一天 build 118 同链路正常。

**Root Cause**: 团队分发证书 0C4DC782…(SHA-1 62B9DB31…) 已被吊销，但证书实体
仍留在登录钥匙串里；`-exportArchive` 的 automatic 签名在解析 Apple Distribution
身份时选中这张死证并直接判失效。ASC 上的 App Store 描述文件其实全部绑着有效
证书（15CC35EA…），非档案问题。注意 xcodebuild 报错里的 serial 会吞掉前导 0
（C4DC782… = 0C4DC782…）。

**Resolution**: `security delete-certificate -Z 62B9DB31…` 删除死证后，同参数
导出立即成功；顺带从 ASC 重新下载安装了三份 App Store 描述文件（本机档案刷新，
非必需但做了）。预防：证书轮换后应同步清理钥匙串旧实体。

**Metadata**
- Pattern-Key: drel.release.revoked-distribution-cert-export
- Recurrence-Count: 1
- First-Seen: 2026-10-30
- Last-Seen: 2026-10-30
