import XCTest

final class PWAAppCatalogTests: XCTestCase {
    func testSignedCatalogListsAppsAndShowsTrustDetails() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--show-pwa-app-center",
            "--clear-last-session"
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

        let dataTemplate = app.buttons["pwaCatalog.app.dev.drel.data-template"]
        XCTAssertTrue(dataTemplate.waitForExistence(timeout: 20), "The signed catalog should include the data template")
        XCTAssertTrue(app.buttons["pwaCatalog.app.dev.drel.offline-demo"].exists)
        XCTAssertTrue(app.buttons["pwaCatalog.app.dev.drel.offline-network-demo"].exists)
        dataTemplate.tap()

        XCTAssertTrue(app.staticTexts["来源与签名"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["能力声明"].exists)
        XCTAssertTrue(app.staticTexts["允许的路由"].exists)
        XCTAssertTrue(app.buttons["pwaCatalog.open"].exists)
        XCTAssertTrue(app.buttons["pwaCatalog.addToHome"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "signed-app-catalog-detail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
