# Drel 权限三档验收自动化（2026-10-21，第二轮样式与交互更新后复验）

模拟器：`Drel-Flow-Verify`（iPhone 17 Pro / iOS 27.0）。
`simctl location` 预设 31.2304,121.4737；定位系统权限预授。

## 结果（第二轮）

| 套件 | 结果 |
|---|---|
| `PWAPermissionFlowTests`（4 例） | 4/4 通过 |
| `PWAPermissionTests`（13 例） | 13/13 通过 |
| 崩溃扫描 | total: 0 |

## 第二轮新增/变更（对照用户验收反馈）

1. 授权面板「始终允许」下方新增快捷入口「查看与管理授权 · 权限与原生能力 →」
   （框架静态钩子 `HTMLAppPermissionPromptPresenter.permissionCenterOpener` +
   App 侧全屏推入）；跳转等同取消，下次调用重新询问。test04 锁定。
2. 权限与能力页全屏无底部 tab：长按入口与面板入口均 `hidesBottomBarWhenPushed`。
   test04 断言 `app.tabBars.count == 0`。
3. 能力卡样式：授权范围改为绿色胶囊芯片（「位置」+「始终允许」芯片），替代
   「位置 · 始终允许」拼接文案。UILabel 芯片实测 AX 有 frame 但像素不渲染，
   改用 disabled UIButton 渲染可靠。
4. 主屏幕添加引导重构为单页：合并「打开入口页/我已在 Safari 完成添加」为单一
   主按钮——点击后原位变「我已添加，完成」，再点完成关闭（testHomeShortcutGuideOpensDesktopEntry
   断言状态机）；弹窗默认 large 档，内容（应用身份/步骤图/说明/按钮）完整可见，
   修复 medium 档裁切。
5. 「允许一次后下次再弹」再次由 test02 复验通过（本轮与上轮均绿）。

## 用例覆盖

1. test01：Demo 页「＋ 添加到主屏幕」入口存在；点击弹窗打开，可关闭。
2. test02：面板「允许一次」在「始终允许」前；允许一次返回坐标后第二次调用
   必须重新弹面板；权限中心空状态。
3. test03：始终允许后第二次调用免面板直返；权限中心列出「位置 · 始终允许」
   芯片行并可撤销（取消可反悔/确认生效）；撤销后空状态；再次调用重新弹面板。
4. test04：面板快捷入口跳转全屏权限中心（无 tab 栏），空状态保持。
5. 旧套件 13 例回归全绿（含合并按钮状态机、长按引导、沉浸菜单权限中心入口）。

## 截图（screenshots/）

- flow-01：Demo 页入口、引导弹窗全貌（large 档内容完整）
- flow-02：面板顺序与配色、允许一次后重复弹窗、空状态
- flow-03：授权列表（含绿色芯片）、撤销确认、撤销后空状态、重复弹窗
- flow-04：面板入口跳转的全屏权限中心（无 tab）
- guide-safari-entry-page：Safari 入口页部署效果

## 环境备注

- 模拟器 location 预设会在长时间后失效（kCLErrorDomain 0），复跑前执行：
  `xcrun simctl location <udid> set 31.2304,121.4737`
- App 侧/框架侧改动均未提交；发版需打 build 102 上 TestFlight。

命令：

```bash
xcodebuild test-without-building -workspace Drel.xcworkspace -scheme Drel \
  -derivedDataPath /tmp/wbk-dd-flowtests \
  -destination 'platform=iOS Simulator,id=6EDF218F-03A2-47BB-9515-068EA8C7475D' \
  -only-testing:DrelUITests/PWAPermissionFlowTests \
  -resultBundlePath /tmp/drel-flow-results.xcresult
```

## 用例覆盖（对照 2026-10-21 用户验收清单）

1. `test01PhoneShortcutEntryOpensGuidePopup`：Demo 页「＋ 添加到主屏幕」入口存在；
   点击弹出 iPhone 主屏幕添加引导弹窗，可关闭。
2. `test02OnceScopeRepromptsAndCenterStaysEmpty`：面板「允许一次」在「始终允许」之前；
   允许一次返回坐标后，**第二次调用必须重新弹面板**（硬性要求）；
   权限与能力页保持空状态（允许一次不入列表）。
3. `test03AlwaysScopeFastPathAndCenterRevoke`：始终允许后第二次调用免面板直返坐标；
   权限与能力页（全屏）列出「位置 · 始终允许」，撤销按钮先取消可反悔、确认后撤销；
   撤销后回到空状态，再次调用重新弹面板。

## 修复的问题（代码）

- 框架 `HTMLAppPermissionPromptPresenter`：允许一次在前（蓝）、始终允许在后（绿），
  取消默认推荐态；补上 `pwa.permission.scopes` 标识（系统拒绝引导态此前无法隐藏按钮）。
- 框架 `HTMLAppRuntime`：授权范围按用户面板选择记录（声明 scope 不得覆盖「允许一次」）；
  非 `.always` 授权不再自动放行也不误拒，一律重新询问；
  无 actionIdentity 的撤销删除该能力全部变体（v2 `|action:` 后缀授权此前撤不掉）。
- 框架 `HTMLAppGatewayOnboarding.activate`：同一网关刷新保留非本网关报告管理的授权
  （官方网关校验完成后曾整体清空 fixture 刚授予的「始终允许」）。
- 框架 `WebAddToHomeScreenHandler` + `WebBridgeHostCapabilityPolicy.phoneHomeScreenGuidePresenter`：
  `addToHomeScreen {placement:"phoneHomeScreen"}` 弹出主屏幕添加引导。
- App `AppDelegate`：UI fixture 种子先激活官方网关，保证会话内 gatewayIdentity 稳定。
- App `PWAPermissionCenterViewController`：仅「始终允许」授权入列；空状态页；
  撤销按钮 accessibilityValue 回归 capability rawValue（此前存 actionIdentity 致撤销静默失效）。
- App `PWAAppCenterViewController`：权限页无导航栈兜底呈现改为全屏。
- 测试页 `test_resources/pwa-permission/v2-actions.html`、
  `test_resources/action-demo/v1/index.html`：新增「＋ 添加到主屏幕」入口。

## 截图

`screenshots/flow-01..03` 共 9 张，覆盖入口、弹窗、面板顺序与配色、
空状态、授权列表、撤销确认、撤销后空状态、重新弹面板。

## 未完成（待发版线）

- `action-demo` 页面对外部署（drel.app/test/actions/）随站点发版。
- App 侧改动需打包 build 102 上 TestFlight 真机复验。
