import XCTest

/// Covers the VOT strong-offline journey on the simulator: install two
/// identities, open each one, prove the page is visible, and prove the local
/// diagnostics record the package, navigation, page and API stages.
final class OfflineVOTDiagnosticsTests: XCTestCase {
    private let app = XCUIApplication()
    private let identities = [
        "app.example.invalid",
        "app.legacy.example.invalid"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--UITesting", "-UITesting", "--register-vot-offline-fixtures"]
        app.launch()
    }

    func testBothVOTIdentitiesOpenOfflineAndRecordDiagnostics() throws {
        for identity in identities {
            let tile = app.descendants(matching: .any)
                .matching(identifier: "pwaHome.app.\(identity)")
                .firstMatch
            var scrolls = 0
            while (!tile.exists || !tile.isHittable) && scrolls < 12 {
                app.swipeUp()
                scrolls += 1
            }
            XCTAssertTrue(tile.waitForExistence(timeout: 25), "Missing home tile for \(identity)")
            tile.tap()

            let browser = app.descendants(matching: .any)
                .matching(identifier: "browserManager.webView")
                .firstMatch
            XCTAssertTrue(browser.waitForExistence(timeout: 20), "Offline app should open for \(identity)")

            // The VOT login card is the visible proof that the local entrypoint,
            // its CSS and its JS all loaded inside WKWebView.
            XCTAssertTrue(
                app.staticTexts["让想法继续生长。"].waitForExistence(timeout: 20),
                "VOT login shell should be visible offline for \(identity)"
            )

            let nativeExit = app.descendants(matching: .any)
                .matching(identifier: "browserManager.immersiveReturnButton")
                .firstMatch
            XCTAssertTrue(nativeExit.waitForExistence(timeout: 5))
            let collapsedFrame = nativeExit.frame
            nativeExit.tap()
            app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            ).withOffset(
                CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
            ).tap()

            let homeTab = app.tabBars.buttons["首页"]
            if homeTab.waitForExistence(timeout: 3) {
                homeTab.tap()
            }
        }

        // Diagnostics live in the release settings list, not only in DEBUG.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["tab.settings"].tap()

        let diagnosticsRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "离线应用诊断")
        ).firstMatch
            .firstMatch
        var scrolls = 0
        while !diagnosticsRow.exists && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        let settingsShot = XCUIScreen.main.screenshot()
        let settingsAttachment = XCTAttachment(screenshot: settingsShot)
        settingsAttachment.name = "offline-diagnostics-settings.png"
        settingsAttachment.lifetime = .keepAlways
        add(settingsAttachment)
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 10), "Settings should expose 离线应用诊断")
        diagnosticsRow.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "offlineDiagnostics.root")
                .firstMatch
                .waitForExistence(timeout: 10),
            "Offline diagnostics screen should render"
        )

        for identity in identities {
            XCTAssertTrue(
                app.staticTexts[identity].waitForExistence(timeout: 10),
                "Diagnostics should keep both VOT identities separate: \(identity)"
            )
        }
    }

    func testWhiteScreenOfflineEntrypointFallsBackOnlineAndRecordsStage() throws {
        app.launchArguments.append("--vot-white-screen-fixture")
        app.terminate()
        app.launch()

        let tile = app.descendants(matching: .any)
            .matching(identifier: "pwaHome.app.app.example.invalid")
            .firstMatch
        var scrolls = 0
        while (!tile.exists || !tile.isHittable) && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 25))
        tile.tap()

        XCTAssertTrue(
            app.staticTexts["让想法继续生长。"].waitForExistence(timeout: 30),
            "A blank offline entrypoint should fall back to the online VOT page"
        )

        let nativeExit = app.descendants(matching: .any)
            .matching(identifier: "browserManager.immersiveReturnButton")
            .firstMatch
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 5))
        let collapsedFrame = nativeExit.frame
        nativeExit.tap()
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()

        let settingsTab = app.tabBars.buttons["tab.settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        let diagnosticsRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "离线应用诊断")
        ).firstMatch
        var settingsScrolls = 0
        while !diagnosticsRow.exists && settingsScrolls < 12 {
            app.swipeUp()
            settingsScrolls += 1
        }
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 10))
        diagnosticsRow.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "在线页面")
            ).firstMatch.waitForExistence(timeout: 10),
            "Diagnostics should identify the online fallback as the actual load source"
        )
    }

    func testInvalidWorkspaceTokenRecordsUnauthorizedAPIStage() throws {
        let tile = app.descendants(matching: .any)
            .matching(identifier: "pwaHome.app.app.example.invalid")
            .firstMatch
        var scrolls = 0
        while (!tile.exists || !tile.isHittable) && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 25))
        tile.tap()

        let tokenField = app.webViews.secureTextFields.firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 20), "VOT login should expose its token field")
        tokenField.tap()
        tokenField.typeText("definitely-invalid-test-key")
        let returnKey = app.keyboards.buttons["return"]
        if returnKey.waitForExistence(timeout: 3) {
            returnKey.tap()
        }

        let submit = app.webViews.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "进入工作台")
        ).firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 8))
        submit.tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "工作台密钥已失效")
            ).firstMatch.waitForExistence(timeout: 20),
            "The invalid test token should return VOT to the login shell"
        )

        closeImmersiveBrowser()
        let settingsTab = app.tabBars.buttons["tab.settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        let diagnosticsRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "离线应用诊断")
        ).firstMatch
        var settingsScrolls = 0
        while !diagnosticsRow.exists && settingsScrolls < 12 {
            app.swipeUp()
            settingsScrolls += 1
        }
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 10))
        diagnosticsRow.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "apiUnauthorized")
            ).firstMatch.waitForExistence(timeout: 10),
            "Diagnostics should classify invalid credentials separately from network failure"
        )
    }

    func testDeleteRedownloadAndColdRestart() throws {
        let identity = identities[0]
        let tile = app.descendants(matching: .any)
            .matching(identifier: "pwaHome.app.\(identity)")
            .firstMatch
        var scrolls = 0
        while (!tile.exists || !tile.isHittable) && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 25))

        tile.press(forDuration: 1.2)
        let delete = app.sheets.buttons["删除离线包"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 8), "Installed package should expose delete")
        delete.tap()
        let confirmDelete = app.alerts.buttons["删除"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 8), "Delete should require explicit confirmation")
        confirmDelete.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "离线包已删除")
            ).firstMatch.waitForExistence(timeout: 10),
            "Delete should complete"
        )

        tile.tap()
        XCTAssertTrue(
            app.staticTexts["让想法继续生长。"].waitForExistence(timeout: 25),
            "After deletion the app should open its online page"
        )
        closeImmersiveBrowser()

        tile.press(forDuration: 1.2)
        let download = app.sheets.buttons.matching(
            NSPredicate(format: "label CONTAINS '离线包'")
        ).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 8), "Deleted package should expose download")
        download.tap()
        _ = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "离线包已准备完成")
        ).firstMatch.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 2)

        app.terminate()
        app.launch()
        var coldScrolls = 0
        while (!tile.exists || !tile.isHittable) && coldScrolls < 12 {
            app.swipeUp()
            coldScrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 25))
        tile.tap()
        XCTAssertTrue(
            app.staticTexts["让想法继续生长。"].waitForExistence(timeout: 20),
            "The redownloaded offline app should survive a cold restart"
        )
    }

    private func closeImmersiveBrowser() {
        let nativeExit = app.descendants(matching: .any)
            .matching(identifier: "browserManager.immersiveReturnButton")
            .firstMatch
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 5))
        let collapsedFrame = nativeExit.frame
        nativeExit.tap()
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()
        let homeTab = app.tabBars.buttons["首页"]
        if homeTab.waitForExistence(timeout: 3) {
            homeTab.tap()
        }
    }
}
