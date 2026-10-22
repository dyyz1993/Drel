# Drel 权限/能力回归（2026-10-22 23:08）

- 模拟器：Drel-Flow-Verify（6EDF218F-03A2-47BB-9515-068EA8C7475D）
- 结果：**19 passed / 0 failed**
- 崩溃：0

## 用例
```
Test Case '-[DrelUITests.ClipboardReopenTests testClipboardAlwaysGrantSurvivesColdStart]' passed (41.599 seconds).
Test Case '-[DrelUITests.PWAPermissionFlowTests test01PhoneShortcutEntryOpensGuidePopup]' passed (19.356 seconds).
Test Case '-[DrelUITests.PWAPermissionFlowTests test02OnceScopeRepromptsAndCenterStaysEmpty]' passed (31.384 seconds).
Test Case '-[DrelUITests.PWAPermissionFlowTests test03AlwaysScopeFastPathAndCenterRevoke]' passed (43.296 seconds).
Test Case '-[DrelUITests.PWAPermissionFlowTests test04PromptEntryOpensFullscreenPermissionCenter]' passed (18.962 seconds).
Test Case '-[DrelUITests.PWAPermissionFlowTests test05AlwaysGrantSurvivesAppRelaunch]' passed (44.048 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testBluetoothWithoutSignedActionIsDeniedWithoutPrompt]' passed (14.476 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testClipboardWithoutSignedActionIsDeniedWithoutPrompt]' passed (13.402 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testGrantedCapabilityCanBeReviewedAndRevoked]' passed (16.068 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testHomeShortcutGuideOpensDesktopEntry]' passed (21.114 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testHomeTileLongPressShowsSettingsAndPhoneShortcutGuide]' passed (22.951 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testInstalledOfflinePackageShowsHomeBadge]' passed (26.772 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testManagedPWAExposesPermissionCenterFromImmersiveHostMenu]' passed (10.836 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testPWAAppDetailsExposeDeclaredAndGrantedCapabilities]' passed (13.964 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testV2AddToHomeScreenShowsVersionOnDrelHome]' passed (19.312 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testV2ClipboardPromptsOnceThenReusesSignedGrant]' passed (14.639 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testV2FullscreenUsesGestureWithoutPermissionPromptAndKeepsNativeExit]' passed (17.179 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testV2LocationRequiresSignedGrantBeforeSystemPrompt]' passed (14.925 seconds).
Test Case '-[DrelUITests.PWAPermissionTests testV2ShareUsesSystemSheetWithoutExtraPermissionPrompt]' passed (14.039 seconds).
```
## 可视化证据
- `drel-permission-regression.mp4`：回归全程录屏
- `animations/<用例名>.webp`：每用例截图序列动画
- `animations/full-run.webp`：全程 1fps 抽样动画
- `screenshots/`：全部原始截图
- `frames/`：视频关键帧（首/中/尾）
