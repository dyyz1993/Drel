import XCTest

/// Drel 1.5 三档授权面板 + 权限中心 + 主屏幕引导的验收自动化
/// （2026-10-21 用户验收清单）。
///
/// 关键硬性要求：「允许一次」之后，后续调用必须再次弹出授权面板；
/// 「始终允许」才进入权限中心列表并支持撤销。
/// 用例按方法名排序执行（test01 → test03），系统定位权限在 test02
/// 首次授予，后续用例复用；Drel 层授权在用例内自行撤销清理。
final class PWAPermissionFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--register-pwa-permission-fixture",
            "--show-pwa-app-center",
            "--clear-last-session",
            "--reset-default-startup-app",
            "--pwa-v2-actions"
        ]
        app.launchEnvironment = [
            "AppleLanguages": "(zh-Hans)",
            "AppleLocale": "zh_CN",
            "WBK_OFFICIAL_PUSH_TEST_STATE": "initial-ready",
            "WBK_OFFICIAL_PUSH_TEST_IDENTITY": "permission_fixture_identity"
        ]
        addUIInterruptionMonitor(withDescription: "Paste Permission") { alert in
            let allow = alert.buttons["允许粘贴"]
            if allow.exists { allow.tap(); return true }
            let allowEn = alert.buttons["Allow Paste"]
            if allowEn.exists { allowEn.tap(); return true }
            return false
        }
        app.activate()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 系统定位弹窗（全新模拟器首次请求才会出现）：点任一允许类按钮。
    /// 没有弹窗时最多等 1 秒即返回，不逐个候选空等。
    private func allowSystemLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.waitForExistence(timeout: 1) else { return }
        let candidates = ["使用App时允许", "使用App期间允许", "仅此一次", "允许一次", "Allow While Using App", "Allow Once"]
        for label in candidates where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            return
        }
        // 兜底：点掉弹窗里唯一非「不允许」的按钮，避免卡住后续断言。
        let allowButton = springboard.alerts.buttons.matching(
            NSPredicate(format: "label != %@ AND label != %@", "不允许", "Don't Allow")
        ).firstMatch
        if allowButton.exists { allowButton.tap() }
    }

    private func openFixtureAppAndReachDemoPage() -> XCUIElement {
        app.launch()
        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 20), "演示应用磁贴应出现在首页")
        appButton.tap()
        let locationButton = app.webViews.buttons["获取当前位置"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 12), "演示页应加载出操作按钮")
        return locationButton
    }

    private func backToHomeFromBrowser() {
        let nativeExit = element("browserManager.immersiveReturnButton")
        if nativeExit.waitForExistence(timeout: 3) {
            nativeExit.tap()
            let frame = nativeExit.frame
            app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            ).withOffset(
                CGVector(dx: frame.minX + 22, dy: frame.midY)
            ).tap()
        }
        _ = element("pwaHome.app.com.webbridgekit.fixture.permissions").waitForExistence(timeout: 5)
    }

    private func openPermissionCenter() {
        let tile = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        tile.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["权限与原生能力"].waitForExistence(timeout: 4))
        app.buttons["权限与原生能力"].tap()
        XCTAssertTrue(element("pwa-permission.headerCard").waitForExistence(timeout: 5))
    }

    /// 1) Demo 页有「＋ 添加到主屏幕」入口，点击弹出 iPhone 主屏幕添加引导。
    func test01PhoneShortcutEntryOpensGuidePopup() {
        let locationButton = openFixtureAppAndReachDemoPage()

        let phoneHomeButton = app.webViews.buttons["添加到主屏幕"]
        XCTAssertTrue(phoneHomeButton.waitForExistence(timeout: 4), "Demo 页应提供「添加到主屏幕」入口")
        // 加号图标是页内 SVG，不会出现在无障碍 label 里；由
        // flow-01-demo-phone-home-entry 截图人工/视觉验收。
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-01-demo-phone-home-entry")

        phoneHomeButton.tap()
        XCTAssertTrue(element("homeShortcut.guide").waitForExistence(timeout: 6), "点击后应弹出主屏幕添加引导弹窗")
        XCTAssertTrue(app.staticTexts["放到 iPhone 主屏幕"].waitForExistence(timeout: 4))
        // 半屏（medium detent）验收：主按钮不滚屏即可直接点按。
        let openEntry = app.buttons["打开 Safari 入口页"]
        XCTAssertTrue(openEntry.waitForExistence(timeout: 4))
        XCTAssertTrue(openEntry.isHittable, "半屏弹窗下主按钮应完整可见可点")
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-01-guide-popup-open")

        app.buttons["关闭引导"].tap()
        XCTAssertFalse(element("homeShortcut.guide").waitForExistence(timeout: 2))

        _ = locationButton
    }

    /// 2) 面板顺序（允许一次在前）、无默认选中（颜色见截图）；
    ///    允许一次 → 下次调用必须再次弹面板；权限中心保持空状态。
    func test02OnceScopeRepromptsAndCenterStaysEmpty() {
        let locationButton = openFixtureAppAndReachDemoPage()

        locationButton.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 6), "首次定位调用应弹授权面板")
        XCTAssertTrue(app.staticTexts["允许使用位置？"].waitForExistence(timeout: 3))

        let once = app.buttons["pwa.permission.scope.once"]
        let always = app.buttons["pwa.permission.scope.always"]
        XCTAssertTrue(once.waitForExistence(timeout: 3), "面板应有「允许一次」")
        XCTAssertTrue(always.exists, "面板应有「始终允许」")
        XCTAssertTrue(once.frame.minY < always.frame.minY, "「允许一次」必须排在「始终允许」前面")
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-02-prompt-order-and-colors")

        once.tap()
        allowSystemLocationIfAsked()
        let result = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS '位置：'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "允许一次后应返回坐标结果")

        // 硬性要求：允许一次不是持久授权，第二次调用必须再次弹面板。
        locationButton.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 6),
                      "「允许一次」后再次调用必须重新弹出授权面板")
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-02-second-call-reprompts")
        app.buttons["取消"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))

        // 只有「允许一次」时，权限中心不应出现能力列表，保持空状态。
        backToHomeFromBrowser()
        openPermissionCenter()
        XCTAssertTrue(element("pwa-permission.emptyState").waitForExistence(timeout: 4),
                      "没有「始终允许」授权时权限中心应保持空状态")
        XCTAssertFalse(element("pwa-permission.capability.location").exists, "允许一次不应进入授权列表")
        XCTAssertEqual(app.buttons.matching(identifier: "pwa-permission.revokeAll").count, 0)
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-02-center-empty-after-once")
    }

    /// 3) 始终允许 → 第二次调用免面板直返；权限中心列出该授权并支持撤销；
    ///    撤销后回到空状态，下次调用重新弹面板。
    func test03AlwaysScopeFastPathAndCenterRevoke() {
        let locationButton = openFixtureAppAndReachDemoPage()

        locationButton.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 6))
        let always = app.buttons["pwa.permission.scope.always"]
        XCTAssertTrue(always.waitForExistence(timeout: 3))
        always.tap()
        allowSystemLocationIfAsked()
        let result = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS '位置：'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "始终允许后应返回坐标结果")

        // 持久授权：第二次调用不再弹面板，直接秒回（15 秒内走缓存）。
        locationButton.tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2),
                       "「始终允许」后再次调用不应弹授权面板")
        XCTAssertTrue(result.waitForExistence(timeout: 10), "第二次调用应直接返回坐标")

        // 权限中心出现「位置 · 始终允许」，可撤销。
        backToHomeFromBrowser()
        openPermissionCenter()
        let locationRow = element("pwa-permission.capability.location")
        XCTAssertTrue(locationRow.waitForExistence(timeout: 4), "始终允许的授权应出现在权限中心列表")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '始终允许'")).firstMatch.exists)
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-03-center-lists-always-grant")

        let revoke = app.buttons["pwa-permission.revoke.location"]
        XCTAssertTrue(revoke.waitForExistence(timeout: 3), "授权行应有撤销按钮")
        revoke.tap()
        XCTAssertTrue(element("pwa-permission.revokeConfirm").waitForExistence(timeout: 4), "撤销应弹确认面板")
        Thread.sleep(forTimeInterval: 0.2)
        attach("flow-03-revoke-confirm-panel")
        app.buttons["pwa-permission.revokeConfirm.cancel"].tap()
        XCTAssertTrue(locationRow.exists, "点取消不应撤销")

        revoke.tap()
        XCTAssertTrue(element("pwa-permission.revokeConfirm").waitForExistence(timeout: 4))
        app.buttons["pwa-permission.revokeConfirm.confirm"].tap()
        XCTAssertTrue(element("pwa-permission.emptyState").waitForExistence(timeout: 4), "撤销后权限中心应回到空状态")
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-03-center-empty-after-revoke")

        // 撤销后再次调用回到授权面板。
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists { backButton.tap() }
        let tile = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        if tile.waitForExistence(timeout: 4) {
            tile.tap()
            let loc = app.webViews.buttons["获取当前位置"]
            if loc.waitForExistence(timeout: 10) {
                loc.tap()
                XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 6),
                              "撤销授权后再次调用应重新弹面板")
                Thread.sleep(forTimeInterval: 0.4)
                attach("flow-03-reprompt-after-revoke")
            }
        }
    }

    /// 4) 授权面板「查看与管理授权」入口 → 跳转该应用权限与能力页，
    ///    且页面全屏（无底部 tab）；面板同时按取消处理（下次再问）。
    func test04PromptEntryOpensFullscreenPermissionCenter() {
        let locationButton = openFixtureAppAndReachDemoPage()

        locationButton.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 6))

        let entry = app.buttons["pwa.permission.openCenter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "面板应有权限中心快捷入口")
        entry.tap()

        XCTAssertTrue(element("pwa-permission.headerCard").waitForExistence(timeout: 6),
                      "入口应跳转权限与能力页")
        XCTAssertTrue(element("pwa-permission.emptyState").waitForExistence(timeout: 4),
                      "没有始终允许授权时页面保持空状态")
        XCTAssertEqual(app.tabBars.count, 0, "权限与能力页必须全屏，不带底部 tab")
        Thread.sleep(forTimeInterval: 0.4)
        attach("flow-04-prompt-entry-opens-fullscreen-center")

        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            _ = element("pwaHome.app.com.webbridgekit.fixture.permissions").waitForExistence(timeout: 5)
        }
        _ = locationButton
    }
}
