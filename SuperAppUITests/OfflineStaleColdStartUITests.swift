import XCTest

/// Real-app cold-start chain for the verified stale-package fallback:
/// install the packaged VOT 0.4.10.4 fixture through the DEBUG bootstrap,
/// terminate, cold start, tap the actual home tile
/// (pwaHome.app.app.vot.example.invalid), and assert the local page renders
/// (offline notice, no online failure alert) and the Settings diagnostics
/// page reports the offline package source. The app's network policy is
/// driven by the DEBUG confirmed-offline override; host networking is never
/// modified, and the page's API base is stubbed to an unreachable loopback
/// port inside that webview only.
final class OfflineStaleColdStartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testColdStartTileOpensLocalPackageAndDiagnosticsReportsOfflinePackage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--e2e-skip-gateway-bootstrap"]
        app.launchEnvironment["E2E_VOT_FIXTURE_DATA"] = Self.prepareFixture()

        // First launch: the fixture bootstrap installs and registers the app.
        app.launch()
        // The tile's accessibility element is exposed as an Other wrapper
        // around the tappable Button, so the identifier must be matched
        // across element types (same pattern as OfflineVOTDiagnosticsTests).
        let tile = app.descendants(matching: .any)
            .matching(identifier: "pwaHome.app.app.vot.example.invalid")
            .firstMatch
        var scrolls = 0
        while (!tile.exists || !tile.isHittable) && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "tile missing: \(app.debugDescription)")

        // Cold start: terminate and relaunch with the same fixture arguments.
        app.terminate()
        app.launch()
        scrolls = 0
        while (!tile.exists || !tile.isHittable) && scrolls < 12 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        tile.tap()

        // The immersive browser must open with the local fixture page; the
        // page shows its offline notice because its API base is an
        // unreachable loopback port.
        let browser = app.descendants(matching: .any)
            .matching(identifier: "browserManager.webView")
            .firstMatch
        XCTAssertTrue(
            browser.waitForExistence(timeout: 20),
            "immersive browser did not open: \(app.debugDescription)"
        )
        let offlineNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "无法连接工作台")
        ).firstMatch
        XCTAssertTrue(
            offlineNotice.waitForExistence(timeout: 15),
            "offline notice missing from local page: \(app.debugDescription)"
        )
        XCTAssertFalse(
            app.alerts.staticTexts["无法打开应用"].exists,
            "a launch failure alert means resolution did not take the offline path"
        )

        // Leave the immersive browser and verify diagnostics via Settings.
        // Tapping the collapsed capsule expands it; the proven exit pattern
        // (OfflineVOTDiagnosticsTests) taps the capsule, then the point
        // beside it, then returns to the Home tab.
        let returnButton = app.descendants(matching: .any)
            .matching(identifier: "browserManager.immersiveReturnButton")
            .firstMatch
        XCTAssertTrue(returnButton.waitForExistence(timeout: 10))
        let collapsedFrame = returnButton.frame
        returnButton.tap()
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()
        let homeTab = app.tabBars.buttons["首页"]
        if homeTab.waitForExistence(timeout: 3) {
            homeTab.tap()
        }

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
        XCTAssertTrue(diagnosticsRow.waitForExistence(timeout: 5))
        diagnosticsRow.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "offlineDiagnostics.root")
                .firstMatch
                .waitForExistence(timeout: 10),
            "offline diagnostics screen did not render: \(app.debugDescription)"
        )
        let attemptRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'offlineDiagnostics.attempt.'")
        ).firstMatch
        XCTAssertTrue(
            attemptRow.waitForExistence(timeout: 10),
            "no diagnostics attempt recorded: \(app.debugDescription)"
        )
        let offlineSource = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "离线包")
        ).firstMatch
        XCTAssertTrue(
            offlineSource.waitForExistence(timeout: 5),
            "diagnostics must report the offline package load source: \(app.debugDescription)"
        )
    }

    /// The runner copies the packaged fixture container (byte-exact .dat,
    /// outside Xcode's resource pipeline) into shared simulator tmp and hands
    /// the path to the app through the launch environment.
    private static func prepareFixture() -> String {
        let bundle = Bundle(for: OfflineStaleColdStartUITests.self)
        guard let url = bundle.url(forResource: "VOT04104", withExtension: "dat") else {
            fatalError("VOT04104.dat missing from UI test bundle")
        }
        let target = URL(fileURLWithPath: "/tmp/drel-e2e-fixture/VOT04104.dat")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            fatalError("fixture copy failed: \(error)")
        }
        return target.path
    }
}
