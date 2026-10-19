# Drel 1.5.0 (96) — Manifest v2 剪贴板/定位授权、分享图标、添加到主页 验证报告

日期：2026-10-19
状态：功能完成、回归通过、TestFlight 上传成功（ASC 状态 VALID，已连接「内部测试」组）。未改动 1.4.1 (89)，未创建/修改任何 App Store Connect 版本或提交。

## 能力清单（全部需签名 Manifest v2 声明 + 前台手势）

| 操作 | JS API | 授权模型 | 说明 |
|---|---|---|---|
| haptic | `callNative('haptic')` | 免隐私弹窗，手势绑定 | 触感反馈 |
| vibrate | `callNative('vibrate')` | 免隐私弹窗，手势绑定 | 短震动 |
| share | `callNative('share', {text,url,iconURL})` | 每次经 iOS 系统分享面板 | 新增同域 `iconURL`，分享面板显示 logo/icon |
| fullscreen | `callNative('fullscreen', {enabled})` | 免隐私弹窗，手势绑定 | 沉浸全屏 |
| clipboard | `callNative('clipboard', {action:'read'|'write'})` | 品牌面板一次授权 → action-level `always`，可撤销 | 新增 |
| location | `callNative('getLocation')` | 品牌面板一次授权 → action-level `always`，可撤销；iOS 仍用 When In Use | 新增 |
| addToHomeScreen | `callNative('addToHomeScreen', {reason})` | 免隐私弹窗；宿主验证已注册 manifest，写入「我的应用」 | 新增；首页磁贴显示名称/图标/应用版本 |

安全边界：
- clipboard/location 声明必须 `always`；其余操作禁止 `always`（SDK 与服务端双重校验）。
- action-level grant 以 `purposeId` 隔离；manifest 移除声明即清理授权。
- `addToHomeScreen` 只能添加当前已注册、来源匹配的 PWA，JS 不能指定任意 URL。
- 分享图标仅允许与页面同源 HTTPS URL，禁止抓取任意第三方图片。
- Drel 1.5 host allowlist：haptic/vibrate/share/fullscreen/clipboard/getLocation/addToHomeScreen。

## 官方演示应用（dev.drel.action-demo v2）

- 静态站：https://drel.app/test/actions/v1/ （已部署，页面显示 Version 2 和全部 7 个操作按钮）
- 网关签名 manifest：https://api.drel.app/api/v1/html-apps/dev.drel.action-demo （cache.version=2，7 个 capabilities_v2 已签名，keyId gw-2026-09-15）
- 服务端版本：2026.10.19-2（/health 已确认）

## 自动化验证

| 门 | 结果 | 证据 |
|---|---|---|
| SDK CoreTests WebJavaScriptBridgeTests（含 2 个新授权回归） | PASS | WebBridgeKit-Framework build/reports/coretests-jsbridge.log |
| SDK JSBridge 回归 6 门 | PASS 6/6 | WebBridgeKit-Framework/build/reports/jsbridge-regression.md |
| 服务端 Manifest v2 签名/授权测试（9 用例，含 clipboard/location always、未知 action 拒绝） | PASS 9/9 | swift test --filter HTMLAppCapabilitiesV2Tests |
| Drel WebView 回归（functional + share + fullscreen UI） | PASS 4/4 | build/reports/drel-app-webview-regression.md |
| Drel 1.5 action policy verifier（扩展 allowlist） | PASS | tools/verify-drel-v2-action-policy.sh |
| Store archive surface（1.5.0 (96)，Apple Distribution，production APNs，Communication Notifications，隐私串，debug fixture 不泄漏） | PASS | DREL_V2_EXPECTED_BUILD=96 verify-drel-v2-store-archive.sh |
| Crash scan | 0 新崩溃（唯一条目为 10-18 旧记录） | scripts/scan-crash-logs.sh |

## 新增自动化测试

- `testDeclaredClipboardUsesActionIdentityAndReusableGrant`：签名 clipboard 声明 → 首次品牌面板授权 → 第二次直接用 action-level grant（purposeId=v2-purpose），无重复弹窗。
- `testLocationWithoutSignedDeclarationIsDeniedEvenWithLegacyCapability`：legacy `capabilities` 里的 location 不再放行；必须签名 v2 声明。
- 服务端：`Rejects always for non-grant actions`、`Accepts always for clipboard and location grants`、`Rejects unknown action`。
- UI：`testV2AddToHomeScreenShowsVersionOnDrelHome` 覆盖添加到主页 → 返回首页 → 磁贴显示「应用版本」；并修正退出胶囊第二次点击落在展开态返回格的交互（坐标点击 22pt 处）。

## 截图

- 首页磁贴版本显示（模拟器，Build 96 debug）：build/reports/v2-runtime-96/simulator-home-version-tiles.png
  - 可见「原生能力演示 · 应用版本 2026.08.13」「Drel Action Demo · 应用版本 1」（Build 96 的版本来自网关 v2 manifest 后将显示为 2）。

## TestFlight

- Archive：/tmp/drel-1-5-0-96-cloud/Drel.xcarchive（1.5.0 (96)，Apple Development 签名的中间产物）
- 导出/上传：automatic App Store signing，destination=upload；xcodebuild -exportArchive 输出「Upload succeeded」
- IPA SHA-256：5edd866985cf40f54b96752a24e349895018c74c6908eb928f879e80456ab0f9
- ASC：build 96 processingState=VALID，betaGroups=内部测试（build id 1f10e8af-a91d-430e-b69e-5cfd5adf7b3c）
- ASC JSON 证据：build/reports/drel-1-5-0-build-96-asc.json

## 边界确认

- `Drel14Release` 仍为 1.4.1 (89)；本次未触碰。
- 未创建/修改 App Store Connect 版本、元数据或提审状态；仅构建分发到内部测试。
- 已知非阻塞：linked SDK 引用蓝牙/定位 API 但 1.5 Store host allowlist 未放行对应能力的 Apple 非致命提醒依旧存在，与 95 相同。
