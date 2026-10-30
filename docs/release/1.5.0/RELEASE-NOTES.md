# Drel 1.5.0 What’s New

Status: owner-review draft. Do not paste into App Store Connect until the
physical-device TestFlight walkthrough is approved and the exact production
gateway demo is available. The copy below describes the same seven actions
the Store build allows; the review notes carry the full detail.

## zh-Hans

```text
Drel 1.5.0 更新

• 原生操作声明：可信 HTML 应用可在签名 Manifest 中声明触感、震动、分享、沉浸全屏、添加到主页
• 更清晰的操作边界：声明只是能力清单，不等于长期授权，也不代表用户已同意交出隐私数据
• 前台手势触发：网页必须在用户点按后的短时间内调用，后台或未声明操作会被拒绝
• 分享更透明：每次分享都打开 iOS 系统分享面板，由你检查内容并选择去向
• 沉浸全屏更清晰：左侧箭头只收起工具条，× 关闭网页，左边缘向右滑返回网页历史且不会误退出
• 首页应用图标会显示离线能力与安装状态；沉浸全屏收起后的侧边控制露出更少，减少遮挡
• 剪贴板与位置由你授权：可信应用需要读取剪贴板或位置时，Drel 会单独征求你的同意
• 授权随时可撤：已授予的剪贴板与位置权限集中在权限中心，一键撤销后立即失效
• 能力范围保持克制：扫码、相册、蓝牙、麦克风、通讯录等敏感能力仍未开放
```

## en-US

```text
What’s new in Drel 1.5.0

• Declared native actions: trusted HTML apps can declare haptic, vibrate, share, immersive fullscreen, and add-to-home-screen actions in an Ed25519-signed manifest
• Clearer boundaries: a declaration is an action inventory, not a long-term grant of user privacy
• Foreground-gesture requirement: pages must call an action shortly after a user tap; undeclared or background calls are rejected
• Transparent sharing: every share opens the native iOS share sheet so you review the content and choose the destination
• Clearer fullscreen controls: the edge arrow only collapses the toolbar, × closes the page, and a left-edge rightward swipe returns through page history without exiting
• Home app badges show offline availability and install state; the collapsed immersive control now takes up less edge space
• Clipboard and location need your permission: when a trusted app asks to read the clipboard or your position, Drel asks you separately
• Revoke any time: granted clipboard and location permissions live in one permission center, and revoking one takes effect immediately
• Restrained capability scope: camera scanning, photos, Bluetooth, microphone, contacts, and other sensitive actions remain unavailable
```

## Submission notes

- Keep the heading synchronized with the editable App Store version. Build 90
  alone does not prove that a 1.5.0 version record has been created.
- Add or trim nothing after owner review without regenerating this document;
  App Review notes must use the same catalog and boundaries.
- Public copy must not claim camera scanning, photo access, Bluetooth,
  microphone, generic device control, or a general
  JavaScript-to-native Bridge.
