# 1.5.0 build 111 — 批量未读推送防连续打开与详情底栏排版验证记录

日期：2026-10-28 ｜ 列车：1.5.0（TestFlight 连续 build，前置 110）

## 1. 批量未读推送防连续打开网页（App）

- 问题：当后台收到大量带 `url` 参数的未读推送时，启动或唤醒 App 触发 `PendingMessageImporter` 批量同步入库，`EngineBootstrap` 先前配置的 `onRoute` 会对每条入库消息自动执行 `openBrowser`，导致所有未读消息的网页被连续推入导航栈，用户必须反复返回。
- 修复：在 `EngineBootstrap.swift` 中强制保持 `onRoute(nil)` 与 `onMessageReceived(nil)`，接收与后台同步阶段仅将消息落库收件箱并同步角标；严格限制只有用户从系统通知屏幕明确点击的那一条通知（走 `UNUserNotificationCenterDelegate.didReceive` → `PushRouter.shared.handle`）才打开其目标地址。
- 验证：`DrelTests.MessageDetailNavigationTests.testEngineBootstrapDoesNotSetAutoRouteOnReceive` 锁定 `onRoute == nil`；`tools/verify-drel-container-only.sh` 第 13 项 `Drel receives URL pushes without auto-navigation` 通过。

## 2. 消息详情底栏「上一条/下一条」胶囊布局调整（App）

- 修复：`MessageDetailViewController.setupSideIndicators` 调整胶囊添加顺序，改为先加 `prevIndicator` 再加 `nextIndicator`，使左侧呈现「‹ 上一条」、右侧呈现「下一条 ›」，符合从左到右的前进阅读逻辑与横向手势拖拽高亮方向。
- 验证：
  - 单元测试：`DrelTests.MessageDetailNavigationTests.testIndicatorOrderPlacesPrevOnLeftAndNextOnRight` 验证 arrangedSubviews 顺序 `[prev, next]`。
  - UI 自动化：`SuperAppUITests.VerifyFixesTests.testInboxMessageDetail` 在模拟器上运行，断言 `prevButton.frame.minX < nextButton.frame.minX` 通过，截图沉淀于 `/tmp/wbk-fix-inbox-detail.png`。

## 3. 门禁与回归

- 单元测试：`xcodebuild test -only-testing:DrelTests` 31/31 全部通过。
- 设计系统与代码规范：`tools/ci-lint.sh` 17 项全通过（0 errors, 3 warnings 均为既有组件废弃标注）。
- 容器边界门禁：`tools/verify-drel-container-only.sh` 40 项全通过。

## 结论

本次修改随 build 111 交付 TestFlight。验收重点：①锁屏/通知栏存在多条带 URL 的未读推送时，点按其中一条只打开对应的一个网页，返回后收件箱保持正常列表；②消息详情底部导航胶囊为左「‹ 上一条」、右「下一条 ›」。
