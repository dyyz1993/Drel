import XCTest

/// 真机等价回归（2026-10-22）：用 Drel15Store 的编译条件构建被测 App
/// （xcodebuild test 时以 SWIFT_ACTIVE_COMPILATION_CONDITIONS 覆盖），
/// 被测应用是真实远程注册的 dev.drel.action-demo（https://drel.app），
/// 与用户 TestFlight 上的场景一致。
///
/// 验证：选「始终允许」→ 杀掉 App → 重开 → 再次定位必须免询问直接返回坐标。
final class ActionDemoPersistenceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // 真机路径：不带任何 fixture / reset 测试参数
        app.launchArguments = ["--ui-testing", "--clear-last-session"]
        app.launchEnvironment = ["AppleLanguages": "(zh-Hans)", "AppleLocale": "zh_CN"]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// 打开 action-demo 并返回定位按钮（若 app 不在首页先回首页）
    private func openActionDemo() -> XCUIElement {
        let tile = element("pwaHome.app.dev.drel.action-demo")
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "action-demo 磁贴应出现在首页（需网关已注册）")
        tile.tap()
        let loc = app.webViews.buttons["获取当前位置"]
        XCTAssertTrue(loc.waitForExistence(timeout: 20), "action-demo 演示页应加载")
        return loc
    }

    private func backToHome() {
        let nativeExit = element("browserManager.immersiveReturnButton")
        if nativeExit.waitForExistence(timeout: 4) {
            nativeExit.tap()
            let frame = nativeExit.frame
            app.windows.firstMatch.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            ).withOffset(CGVector(dx: frame.minX + 22, dy: frame.midY)).tap()
        }
        _ = element("pwaHome.app.dev.drel.action-demo").waitForExistence(timeout: 6)
    }

    private func allowSystemLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.waitForExistence(timeout: 2) else { return }
        for label in ["使用App时允许", "使用App期间允许", "允许一次", "Allow While Using App", "Allow Once"]
        where springboard.buttons[label].exists {
            springboard.buttons[label].tap()
            return
        }
    }

    func testAlwaysGrantSurvivesColdStartOnRealDevicePath() {
        app.activate()
        let loc = openActionDemo()

        // 首次：弹三档面板 → 始终允许 → 系统授权 → 坐标
        loc.tap()
        XCTAssertTrue(element("pwa.permission.prompt").waitForExistence(timeout: 8),
                      "首调应弹三档授权面板")
        attach("ad-first-prompt")
        app.buttons["pwa.permission.scope.always"].tap()
        allowSystemLocationIfAsked()
        let result = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS '位置：'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "始终允许后应返回坐标")
        attach("ad-granted")

        // 杀掉 App 冷启动（真机路径：无任何测试清理参数）
        app.terminate()
        app.launch()

        let loc2 = openActionDemo()
        loc2.tap()

        // 硬性断言 1：不得再弹授权面板
        let promptReappeared = element("pwa.permission.prompt").waitForExistence(timeout: 5)
        attach("ad-after-relaunch")
        XCTAssertFalse(promptReappeared, "「始终允许」必须活过冷启动，不得再弹授权面板")

        // 硬性断言 2：必须直接返回坐标（读回持久授权）
        XCTAssertTrue(result.waitForExistence(timeout: 15), "冷启动后应直接返回坐标（授权被持久读回）")
        attach("ad-cold-start-fast-path")
    }
}
