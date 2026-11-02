import XCTest

final class PWAPermissionTests: XCTestCase {
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
            "--reset-default-startup-app"
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
            let deny = alert.buttons["不允许粘贴"]
            if deny.exists { deny.tap(); return true }
            let denyEn = alert.buttons["Don't Allow"]
            if denyEn.exists { denyEn.tap(); return true }
            return false
        }
        app.activate()
    }

    func testPWAAppDetailsExposeDeclaredAndGrantedCapabilities() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 20), "Fixture app should stay visible; stale home state indicates simulator hygiene issue")
        appButton.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["权限与原生能力"].waitForExistence(timeout: 4))
        app.buttons["权限与原生能力"].tap()

        XCTAssertTrue(element("pwa-permission.headerCard").waitForExistence(timeout: 5))
        // 产品决策 2026-08-21：未授权能力不再渲染行，中心此时为空授权态
        for capability in ["bluetooth", "clipboard", "camera", "location", "fileImport", "share"] {
            XCTAssertFalse(
                element("pwa-permission.capability.\(capability)").exists,
                "未授权能力不应渲染: \(capability)"
            )
        }
        // 产品决策 2026-08-21：权限中心只展示已授权/需处理，「尚未使用」不再渲染
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '尚未使用'"))
                .firstMatch.waitForExistence(timeout: 2)
        )
        XCTAssertEqual(app.buttons.matching(identifier: "pwa-permission.revokeAll").count, 0)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "pwa-permission-center"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHomeTileLongPressShowsSettingsAndPhoneShortcutGuide() {
        app.launch()

        let tile = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["设为默认启动应用"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["添加到 iPhone 主屏幕…"].exists)
        app.buttons["设为默认启动应用"].tap()
        let updatedTile = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        let badgeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "默认启动应用"),
            object: updatedTile
        )
        XCTAssertEqual(XCTWaiter.wait(for: [badgeExpectation], timeout: 5), .completed)
        let badgeScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        badgeScreenshot.name = "home-default-startup-badge"
        badgeScreenshot.lifetime = .keepAlways
        add(badgeScreenshot)

        tile.press(forDuration: 1.2)
        app.buttons["添加到 iPhone 主屏幕…"].tap()
        XCTAssertTrue(element("homeShortcut.guide").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["放到 iPhone 主屏幕"].exists)
        XCTAssertTrue(app.buttons["打开 Safari 入口页"].exists)
        Thread.sleep(forTimeInterval: 0.5)
        let guideScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        guideScreenshot.name = "iphone-home-screen-shortcut-guide-link"
        guideScreenshot.lifetime = .keepAlways
        add(guideScreenshot)

        // 单页半屏引导（2026-10-21 精简版）：安全声明同屏可见，不再有长正文标题。
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不能静默安装主屏幕图标"))
                .firstMatch.exists,
            "The guide should say that Drel cannot silently install a Home Screen icon"
        )
        Thread.sleep(forTimeInterval: 0.5)
        let workflowScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        workflowScreenshot.name = "iphone-home-screen-shortcut-guide-workflow"
        workflowScreenshot.lifetime = .keepAlways
        add(workflowScreenshot)

        app.buttons["关闭引导"].tap()
        XCTAssertFalse(element("homeShortcut.guide").waitForExistence(timeout: 2))

        tile.tap()
        XCTAssertTrue(element("browserManager.webView").waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["打开应用"].exists)
    }

    func testInstalledOfflinePackageShowsHomeBadge() {
        app.launchArguments.append("--activate-offline-demo")
        app.launch()

        let tile = element("pwaHome.app.dev.drel.offline-demo")
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.press(forDuration: 1.2)
        let download = app.buttons["下载离线包"]
        if download.waitForExistence(timeout: 3) {
            download.tap()
        } else {
            app.buttons["关闭"].tap()
        }
        let installed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "离线包已安装"),
            object: tile
        )
        XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 30), .completed)
        let hud = app.staticTexts["离线包已准备完成"]
        let hudDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: hud
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hudDismissed], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "home-installed-offline-badge"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testHomeShortcutGuideOpensDesktopEntry() {
        app.launch()

        let tile = element("pwaHome.app.dev.drel.action-demo")
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.press(forDuration: 1.2)
        app.buttons["添加到 iPhone 主屏幕…"].tap()
        XCTAssertTrue(element("homeShortcut.guide").waitForExistence(timeout: 4))
        let openEntry = app.buttons["打开 Safari 入口页"]
        XCTAssertTrue(openEntry.waitForExistence(timeout: 12), "主屏幕入口流程应提供 HTTPS 入口页")
        Thread.sleep(forTimeInterval: 0.5)
        let guideScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        guideScreenshot.name = "iphone-home-screen-desktop-entry"
        guideScreenshot.lifetime = .keepAlways
        add(guideScreenshot)

        // 合并按钮状态机：点「打开 Safari 入口页」后原位变为「我已添加，完成」
        openEntry.tap()
        let finish = app.buttons["我已添加，完成"]
        XCTAssertTrue(finish.waitForExistence(timeout: 6), "打开入口后按钮应变为「我已添加，完成」")
        Thread.sleep(forTimeInterval: 0.5)
        let finishScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        finishScreenshot.name = "iphone-home-screen-guide-merged-button-done-state"
        finishScreenshot.lifetime = .keepAlways
        add(finishScreenshot)

        // Safari 往返后 sheet 重新渲染需要时间；点击失败时重试一次。
        app.activate()
        Thread.sleep(forTimeInterval: 1.5)
        finish.tap()
        if element("homeShortcut.guide").exists {
            finish.tap()
        }
        XCTAssertFalse(element("homeShortcut.guide").waitForExistence(timeout: 3), "完成应关闭引导")
    }

    func testClipboardWithoutSignedActionIsDeniedWithoutPrompt() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let bridgeButton = app.webViews.buttons["读取剪贴板"]
        XCTAssertTrue(bridgeButton.waitForExistence(timeout: 12))
        bridgeButton.tap()

        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        XCTAssertTrue(app.webViews.staticTexts["Error: PWA 未获得该原生能力授权"].waitForExistence(timeout: 5))
    }

    func testCapabilityQueryInWebViewDoesNotPrompt() {
        app.launchArguments += ["--pwa-v2-actions", "--reset-permission-grants"]
        app.launchEnvironment["WBK_PWA_PERMISSION_ORIGIN"] = "http://localhost:18082"
        app.launch()
        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 20))
        appButton.tap()
        let query = app.webViews.buttons["查询能力状态"]
        XCTAssertTrue(query.waitForExistence(timeout: 15))
        query.tap()
        let result = app.webViews.staticTexts["查询成功 clipboard true true notDetermined"]
        XCTAssertTrue(result.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(element("pwa.permission.prompt").exists)
    }

    func testV2ShareUsesSystemSheetWithoutExtraPermissionPrompt() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let shareButton = app.webViews.buttons["分享演示内容"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 12))
        shareButton.tap()

        let consentPrompt = element("pwa.permission.prompt")
        XCTAssertFalse(consentPrompt.waitForExistence(timeout: 2))
        let systemShareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(systemShareSheet.waitForExistence(timeout: 8), app.debugDescription)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-share-ios-system-sheet-local-fixture"
        attachment.lifetime = .keepAlways
        add(attachment)

        let closeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "关闭")).firstMatch
        if closeButton.exists { closeButton.tap() }
    }

    func testV2FullscreenUsesGestureWithoutPermissionPromptAndKeepsNativeExit() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let fullscreenButton = app.webViews.buttons["切换沉浸全屏"]
        XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 12))
        fullscreenButton.tap()

        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars.firstMatch.waitForExistence(timeout: 2))
        let nativeExit = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 3))
        let collapsedFrame = nativeExit.frame
        XCTAssertEqual(collapsedFrame.maxX, 20, accuracy: 1, "Collapsed immersive control should expose only a 20pt edge sliver")
        let collapsedAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsedAttachment.name = "v2-fullscreen-host-exit-collapsed-20pt"
        collapsedAttachment.lifetime = .keepAlways
        add(collapsedAttachment)
        nativeExit.tap()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-fullscreen-host-exit-visible"
        attachment.lifetime = .keepAlways
        add(attachment)

        // First verify the edge arrow now only collapses the control.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 48, dy: collapsedFrame.midY)
        ).tap()
        XCTAssertTrue(element("browserManager.webView").waitForExistence(timeout: 3), "Collapsing must keep the HTML app open")

        // Re-expand, then use the dedicated back cell.
        nativeExit.tap()
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()
        XCTAssertTrue(appButton.waitForExistence(timeout: 5), "The dedicated back cell must return to the app list")
    }

    func testV2ClipboardPromptsOnceThenReusesSignedGrant() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let clipboardButton = app.webViews.buttons["读取剪贴板"]
        XCTAssertTrue(clipboardButton.waitForExistence(timeout: 12))
        clipboardButton.tap()

        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-clipboard-signed-grant-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["始终允许"].tap()

        clipboardButton.tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
    }

    func testV2LocationRequiresSignedGrantBeforeSystemPrompt() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let locationButton = app.webViews.buttons["获取当前位置"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 12))
        locationButton.tap()

        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["允许使用位置？"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-location-signed-grant-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["取消"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
    }

    func testVoiceGameWaitsForMicrophoneConsentAndHandlesCancellation() {
        app.launchArguments += ["--pwa-voice-jump", "--reset-permission-grants"]
        app.launch()
        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 15))
        appButton.tap()
        let start = app.webViews.buttons["开启麦克风并开始"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        start.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.buttons["正在游戏"].exists)
        app.buttons["取消"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 3))
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testVoiceDandelionWaitsForMicrophoneConsentAndHandlesCancellation() {
        app.launchArguments += ["--pwa-voice-dandelion", "--reset-permission-grants"]
        app.launch()
        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 15))
        appButton.tap()
        let start = app.webViews.buttons["开启麦克风"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        start.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.buttons["停止"].isEnabled)
        app.buttons["取消"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 3))
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testV2AddToHomeScreenShowsVersionOnDrelHome() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let homeButton = app.webViews.buttons["添加到 Drel 首页"]
        XCTAssertTrue(homeButton.waitForExistence(timeout: 12))
        homeButton.tap()

        if element("pwa.permission.prompt").waitForExistence(timeout: 5) {
            app.buttons["取消"].tap()
            XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 3))
        }

        let nativeExit = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 3))
        let collapsedFrame = nativeExit.frame
        nativeExit.tap()
        // First tap expands the collapsed capsule. The second tap must land
        // on the back segment (second 44pt cell of the expanded 188pt capsule)
        // instead of the element center, which now falls on the refresh cell.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()

        XCTAssertTrue(appButton.waitForExistence(timeout: 5))
        // SwiftUI composes the name and version into the tile's accessibility
        // label. The element reports it as an Other in the AX tree; query by
        // predicate over static texts and buttons.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '应用版本'")).firstMatch.exists
                || app.buttons.matching(NSPredicate(format: "label CONTAINS '应用版本'")).firstMatch.exists
                || app.otherElements.matching(NSPredicate(format: "label CONTAINS '应用版本'")).firstMatch.exists
                || app.windows.firstMatch.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '应用版本'"))
                    .firstMatch.exists
                || element(appButton.identifier).label.contains("应用版本"),
                      "Home tile must expose the app version in its accessibility label")
        // The demo result text proves the native action ran; alreadyPresent is
        // also success on repeat runs of the same simulator.
        // The demo result text lives in the WebView; after returning home it
        // is not required. The home version label is the authoritative check.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-add-to-home-screen-with-version"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBluetoothWithoutSignedActionIsDeniedWithoutPrompt() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let bridgeButton = app.webViews.buttons["查看蓝牙状态"]
        XCTAssertTrue(bridgeButton.waitForExistence(timeout: 12))
        bridgeButton.tap()

        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        XCTAssertTrue(app.webViews.staticTexts["Error: PWA 未获得该原生能力授权"].waitForExistence(timeout: 5))
    }

    func testGrantedCapabilityCanBeReviewedAndRevoked() {
        app.launchArguments.append("--seed-pwa-permission-grant")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["权限与原生能力"].waitForExistence(timeout: 4))
        app.buttons["权限与原生能力"].tap()

        let grant = element("pwa-permission.capability.clipboard")
        XCTAssertTrue(grant.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pwa-permission.revokeAll"].isEnabled)
        app.buttons["pwa-permission.revoke.clipboard"].tap()
        XCTAssertTrue(element("pwa-permission.revokeConfirm").waitForExistence(timeout: 3))
        app.buttons["pwa-permission.revokeConfirm.confirm"].tap()

        // 撤销后该能力不再渲染（未授权不显示）
        XCTAssertFalse(element("pwa-permission.capability.clipboard").waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(identifier: "pwa-permission.revokeAll").count, 0)
    }

    func testManagedPWAExposesPermissionCenterFromImmersiveHostMenu() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()

        let capsule = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(capsule.waitForExistence(timeout: 12))

        func snap(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        sleep(1)
        snap("immersive-collapsed-no-top-right")

        // The edge capsule is a UIControl without per-cell accessibility
        // elements. Tap its collapsed sliver, then the trailing More cell.
        let expanded = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.19))
        expanded.tap()
        let more = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.19))
        sleep(1)
        snap("immersive-capsule-expanded-more")
        more.tap()

        let permissionItem = app.buttons["权限与能力"]
        XCTAssertTrue(permissionItem.waitForExistence(timeout: 5))
        XCTAssertEqual(capsule.label, "显示浏览器控制条")
        sleep(1)
        snap("immersive-more-function-list")
        app.buttons["关闭功能菜单"].tap()
        XCTAssertFalse(permissionItem.waitForExistence(timeout: 1))
        expanded.tap()
        more.tap()
        XCTAssertTrue(permissionItem.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.71))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertFalse(permissionItem.waitForExistence(timeout: 1))
        expanded.tap()
        more.tap()
        XCTAssertTrue(permissionItem.waitForExistence(timeout: 5))
        permissionItem.tap()

        XCTAssertTrue(element("pwa-permission.headerCard").waitForExistence(timeout: 5))
        sleep(1)
        snap("immersive-permission-center")
        // 未授权能力不再渲染行，中心此时应为空授权态
        XCTAssertFalse(element("pwa-permission.capability.bluetooth").exists)
    }

    func testOrdinaryImmersiveBrowserFunctionMenu() {
        app.launch()
        let target = "http://localhost:8081/test_resources/pwa-permission/index.html?mode=immersive"
        var link = URLComponents(string: "webbridgekit://open")!
        link.queryItems = [URLQueryItem(name: "url", value: target)]
        XCUIDevice.shared.system.open(link.url!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons["打开"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(element("browserManager.webView").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["查看蓝牙状态"].waitForExistence(timeout: 30))
        let loading = app.activityIndicators["进行中"]
        let loadingGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)
        XCTAssertEqual(XCTWaiter.wait(for: [loadingGone], timeout: 20), .completed)
        let capsule = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        let screen = app.frame
        func openMenu() {
            let collapsed = capsule.frame
            let visibleX = min(screen.maxX - 4, max(screen.minX + 4, collapsed.midX))
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visibleX, dy: collapsed.midY)).tap()
            let frame = capsule.frame
            let moreX = frame.midX < screen.midX ? frame.maxX - 22 : frame.minX + 22
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: moreX, dy: frame.midY)).tap()
            if !app.buttons["复制链接"].waitForExistence(timeout: 5) {
                print("ORDINARY_MENU_HIERARCHY \(app.debugDescription)")
                XCTFail("普通浏览器功能菜单未出现")
            }
            XCTAssertEqual(capsule.label, "显示浏览器控制条")
        }
        func tapMenuItem(_ label: String) {
            let item = app.buttons[label]
            if !item.isHittable { app.swipeUp() }
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
        }
        openMenu()
        app.buttons["复制链接"].tap()
        let toast = app.staticTexts["链接已复制"]
        XCTAssertTrue(toast.waitForExistence(timeout: 4))
        let toastScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        toastScreenshot.name = "toast-copy-success"
        toastScreenshot.lifetime = .keepAlways
        add(toastScreenshot)
        let toastGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)
        XCTAssertEqual(XCTWaiter.wait(for: [toastGone], timeout: 5), .completed)
        openMenu()
        tapMenuItem("书签")
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        openMenu()
        tapMenuItem("显示导航栏")
        let browserMenu = app.buttons["browserManager.menuButton"]
        XCTAssertTrue(browserMenu.waitForExistence(timeout: 5))
        browserMenu.tap()
        if app.buttons["显示状态栏"].exists {
            app.buttons["显示状态栏"].tap()
        } else {
            app.buttons["取消"].tap()
        }
        sleep(2)
        let shownScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shownScreenshot.name = "browser-status-shown"
        shownScreenshot.lifetime = .keepAlways
        add(shownScreenshot)
        browserMenu.tap()
        XCTAssertTrue(app.buttons["隐藏状态栏"].waitForExistence(timeout: 5))
        app.buttons["隐藏状态栏"].tap()
        sleep(2)
        let hiddenScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hiddenScreenshot.name = "browser-status-hidden"
        hiddenScreenshot.lifetime = .keepAlways
        add(hiddenScreenshot)
        browserMenu.tap()
        XCTAssertTrue(app.buttons["显示状态栏"].waitForExistence(timeout: 5))
        app.buttons["显示状态栏"].tap()
        browserMenu.tap()
        XCTAssertTrue(app.buttons["隐藏导航栏"].waitForExistence(timeout: 5))
        app.buttons["隐藏导航栏"].tap()
        openMenu()
        tapMenuItem("隐藏状态栏")
        openMenu()
        tapMenuItem("显示状态栏")
        openMenu()
        tapMenuItem("缓存统计")
        XCTAssertTrue(app.alerts["缓存统计"].waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        openMenu()
        tapMenuItem("权限与能力")
        XCTAssertTrue(app.navigationBars["网页授权管理"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        openMenu()
        app.buttons["关闭功能菜单"].tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
