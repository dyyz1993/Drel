# Drel 1.5: iPhone 主屏幕图文引导

## 本次变更

- 从“我的应用”长按应用后，选择“添加到 iPhone 主屏幕…”进入可展开的原生底部弹窗；初始为半屏，进入后续步骤时展开以完整显示图示。
- 三步说明分别覆盖复制应用专属 `drel://app?app_id=...` 链接、在快捷指令中串接“URL”与“打开 URL”、由用户在快捷指令详情中选择“添加到主屏幕”。图示切换有过渡动画，系统“减少动态效果”开启时不播放位移动画。
- 使用已验证的 Web App Manifest 图标；有图标时可拉起 iOS 分享面板，将图像保存到照片或文件，再由用户在快捷指令中选用。无图标时仅显示首字母，并明确提示不能导出。
- 不是静默安装图标，也不是 Drel 自身的系统“添加到主屏幕”接口。最终名称、图片和安装动作都由用户在快捷指令中确认。

## 自动化

| 验证 | 结果 | 证据 |
|---|---|---|
| UI：长按入口、默认标识、三步引导、关闭后轻点打开应用 | 通过 | `/tmp/drel-home-guide-test-v7.log`，`/tmp/drel-home-guide-v7.xcresult` |
| UI：官方 Drel Action Demo 图标载入、分享面板出现 | 通过 | `/tmp/drel-home-guide-test-v7.log`，`/tmp/drel-home-guide-v7.xcresult` |
| UI：分享面板截图回归 | 通过 | `/tmp/drel-home-guide-test-v8.log`，`/tmp/drel-home-guide-v8.xcresult` |
| Drel15Store / Drel15Release 模拟器编译 | 通过 | `/tmp/drel-home-guide-drel15-build.log` |
| 1.5 动作策略及 1.4.1 版本边界 | 通过 | `bash tools/verify-drel-v2-action-policy.sh` |
| 仓库交付边界 | 7/7 通过 | `/tmp/drel-home-guide-boundaries.log` |
| 新增视图 SwiftLint；补丁空白检查 | 通过 | `swiftlint lint --quiet SuperApp/Sources/Views/PWAHome/PhoneHomeScreenGuideView.swift`；`git diff --check` |
| 模拟器崩溃扫描 | 0 | `/tmp/drel-home-guide-crash-scan.json` |

以上 UI 证据来自 iOS 18.3 模拟器。此轮未跑完整 JSBridge/WebView/release gate；变更仅限宿主 UI 与引导。旧版 1.4.1 和 App Store Connect 未修改；本次未生成或上传新的 TestFlight 构建。

## 截图

- [第 1 步：专属链接](01-link.png)
- [第 2 步：URL 与打开 URL](02-shortcuts.png)
- [第 3 步：添加到主屏幕](03-home-screen.png)
- [官方演示应用图标](04-verified-icon.png)
- [iOS 图标分享面板](05-icon-share-sheet.png)

## 尚需实机验收

1. 安装含本变更的新构建，长按“我的应用”中的 Drel Action Demo，进入引导，确认快捷指令能打开、链接可粘贴、图标可存到照片或文件。
2. 在快捷指令中加入“URL”与“打开 URL”，打开详情，点“添加到主屏幕”并选择刚保存的图标。点 iPhone 桌面图标，应先唤起 Drel 再直接进入 Drel Action Demo，而不是 Safari。
3. 如失败，记录快捷指令两步的配置截图、桌面图标截图、Drel 实际落点及设备 iOS 版本。模拟器 UI 测试不能证明用户完成的系统级主屏幕创建链路。
