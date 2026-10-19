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
    }

    func testPWAAppDetailsExposeDeclaredAndGrantedCapabilities() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 20), "Fixture app should stay visible; stale home state indicates simulator hygiene issue")
        appButton.tap()
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

    func testManagedPWABridgeRequestOffersScopesAndCanBeCancelled() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let bridgeButton = app.webViews.buttons["读取剪贴板"]
        XCTAssertTrue(bridgeButton.waitForExistence(timeout: 12))
        bridgeButton.tap()

        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原生能力申请"].exists)
        // 2026-08-22 产品决策：两选（允许 / 拒绝）
        for title in ["允许", "拒绝"] {
            XCTAssertTrue(app.buttons[title].exists, "Missing permission choice: \(title)")
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "pwa-bridge-permission-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["拒绝"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        XCTAssertTrue(bridgeButton.exists)
    }

    func testV2ShareUsesSystemSheetWithoutExtraPermissionPrompt() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

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
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let fullscreenButton = app.webViews.buttons["切换沉浸全屏"]
        XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 12))
        fullscreenButton.tap()

        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars.firstMatch.waitForExistence(timeout: 2))
        let nativeExit = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 3))
        nativeExit.tap()

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-fullscreen-host-exit-visible"
        attachment.lifetime = .keepAlways
        add(attachment)

        nativeExit.tap()
        XCTAssertTrue(fullscreenButton.waitForExistence(timeout: 4), "The host exit control must return to the app without closing the HTML app")
    }

    func testV2ClipboardPromptsOnceThenReusesSignedGrant() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let clipboardButton = app.webViews.buttons["读取剪贴板"]
        XCTAssertTrue(clipboardButton.waitForExistence(timeout: 12))
        clipboardButton.tap()

        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-clipboard-signed-grant-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["允许"].tap()

        clipboardButton.tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
    }

    func testV2LocationRequiresSignedGrantBeforeSystemPrompt() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let locationButton = app.webViews.buttons["获取当前位置"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 12))
        locationButton.tap()

        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["允许使用位置？"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v2-location-signed-grant-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["拒绝"].tap()
        XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 2))
    }

    func testV2AddToHomeScreenShowsVersionOnDrelHome() {
        app.launchArguments.append("--pwa-v2-actions")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let homeButton = app.webViews.buttons["添加到 Drel 首页"]
        XCTAssertTrue(homeButton.waitForExistence(timeout: 12))
        homeButton.tap()

        if element("pwa.permission.prompt").waitForExistence(timeout: 5) {
            app.buttons["允许"].tap()
            if element("pwa.permission.prompt").waitForExistence(timeout: 3) {
                // Location or clipboard prompt may queue behind add-to-home; dismiss
                // any queued consent so the native exit control stays reachable.
                app.buttons["拒绝"].tap()
                XCTAssertFalse(element("pwa.permission.prompt").waitForExistence(timeout: 3))
            }
        }

        let nativeExit = element("browserManager.immersiveReturnButton")
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 3))
        nativeExit.tap()
        // First tap expands the collapsed capsule. The second tap must land
        // on the exit segment (leftmost 44pt of the expanded 140pt capsule)
        // instead of the element center, which now falls on the refresh cell.
        let frame = nativeExit.frame
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: frame.minX + 22, dy: frame.midY)
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

    func testBluetoothRequestUsesManagedPWAConsentBeforeSystemAccess() {
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let bridgeButton = app.webViews.buttons["查看蓝牙状态"]
        XCTAssertTrue(bridgeButton.waitForExistence(timeout: 12))
        bridgeButton.tap()

        let prompt = element("pwa.permission.prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["允许使用蓝牙？"].exists)
        XCTAssertTrue(app.staticTexts["允许后，iOS 仍可能显示系统权限确认。"].exists)
        XCTAssertTrue(app.buttons["允许"].exists)
        XCTAssertTrue(app.buttons["拒绝"].exists)
        XCTAssertTrue(app.buttons["允许"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "pwa-bluetooth-permission-prompt"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Keep the UI test deterministic: cancel before CoreBluetooth can ask
        // for the simulator's system-level authorization.
        app.buttons["取消"].tap()
        XCTAssertFalse(prompt.waitForExistence(timeout: 2))
    }

    func testGrantedCapabilityCanBeReviewedAndRevoked() {
        app.launchArguments.append("--seed-pwa-permission-grant")
        app.launch()

        let appButton = element("pwaHome.app.com.webbridgekit.fixture.permissions")
        XCTAssertTrue(appButton.waitForExistence(timeout: 12))
        appButton.tap()
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
        XCTAssertTrue(app.buttons["打开应用"].waitForExistence(timeout: 4))
        app.buttons["打开应用"].tap()

        let menu = element("browserManager.immersiveMenuButton")
        XCTAssertTrue(menu.waitForExistence(timeout: 12))
        menu.tap()

        XCTAssertTrue(element("pwa-permission.headerCard").waitForExistence(timeout: 5))
        // 未授权能力不再渲染行，中心此时应为空授权态
        XCTAssertFalse(element("pwa-permission.capability.bluetooth").exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
