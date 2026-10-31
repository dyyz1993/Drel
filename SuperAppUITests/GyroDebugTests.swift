import XCTest

/// Simulator coverage for the managed `sensors` action.
///
/// A simulator has no accelerometer stream, so this test proves the native
/// dispatch reaches CoreMotion and reports the expected hardware limitation.
/// The synthetic-tilt controls then exercise the game loop without pretending
/// that simulator motion data is real-device evidence.
final class GyroDebugTests: XCTestCase {
    func testDebugPanelShowsBridgeDispatchAndSyntheticTiltRunsGame() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Synthetic tilt is simulator coverage; physical tilt needs a real iPhone")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--show-pwa-app-center",
            "--clear-last-session",
            "--reset-app-catalog-activations"
        ]
        app.launchEnvironment = [
            "AppleLanguages": "(zh-Hans)",
            "AppleLocale": "zh_CN"
        ]
        app.launch()

        let manage = app.buttons["pwaHome.manageApps"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()

        let browse = app.buttons["浏览全部应用"]
        XCTAssertTrue(browse.waitForExistence(timeout: 4))
        browse.tap()

        let gyro = app.buttons["pwaCatalog.app.dev.gyro.offline"]
        XCTAssertTrue(gyro.waitForExistence(timeout: 20), "The signed catalog should list the gyro app")
        gyro.tap()
        app.buttons["pwaCatalog.open"].tap()

        let debugButton = app.webViews.buttons["传感器调试"]
        XCTAssertTrue(debugButton.waitForExistence(timeout: 20), "Gyro v7 should expose the sensor debug panel")
        debugButton.tap()
        XCTAssertTrue(app.webViews.staticTexts["Bridge 传感器调试"].waitForExistence(timeout: 4))

        app.webViews.buttons["查询传感器"].tap()
        let success = app.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "lastResult: success")
        ).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 5), "The sensors status call must reach the native handler")

        app.webViews.buttons["启动加速度计"].tap()
        let startCall = app.webViews.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "CALL startAccelerometer")
        ).firstMatch
        XCTAssertTrue(
            startCall.waitForExistence(timeout: 5),
            "The accelerometer subscription must reach the native sensors handler"
        )
        XCTAssertFalse(
            app.webViews.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Action is not enabled by host policy")
            ).firstMatch.exists,
            "Simulator coverage must not stop at the host allowlist"
        )
        let debugAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        debugAttachment.name = "gyro-v7-simulator-bridge-debug-panel"
        debugAttachment.lifetime = .keepAlways
        add(debugAttachment)

        app.webViews.buttons["模拟右倾"].tap()
        app.webViews.buttons["收起调试"].tap()
        app.webViews.buttons["开始游戏"].tap()

        let score = app.webViews.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "得分 ")
        ).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 3))
        let scoreAdvanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", "得分 0 · 最佳 0"),
            object: score
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scoreAdvanced], timeout: 4), .completed)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "gyro-v7-simulator-dispatch-and-synthetic-game"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }
}
