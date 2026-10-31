import XCTest

final class PWAAppCatalogTests: XCTestCase {
    func testSignedCatalogListsAppsAndShowsTrustDetails() {
        let app = launchCatalog()

        let dataTemplate = app.buttons["pwaCatalog.app.dev.drel.data-template"]
        XCTAssertTrue(dataTemplate.waitForExistence(timeout: 20), "The signed catalog should include the data template")
        XCTAssertTrue(app.buttons["pwaCatalog.app.dev.drel.offline-demo"].exists)
        XCTAssertTrue(app.buttons["pwaCatalog.app.dev.drel.offline-network-demo"].exists)
        let catalogRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pwaCatalog.app.")
        ).count
        XCTAssertGreaterThanOrEqual(catalogRows, 6, "The catalog should list every signed app")

        let catalogAttachment = XCTAttachment(screenshot: app.screenshot())
        catalogAttachment.name = "signed-app-catalog-list"
        catalogAttachment.lifetime = .keepAlways
        add(catalogAttachment)
        dataTemplate.tap()

        XCTAssertTrue(app.staticTexts["来源与签名"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["能力声明"].exists)
        XCTAssertTrue(app.staticTexts["允许的路由"].exists)
        XCTAssertTrue(app.buttons["pwaCatalog.open"].exists)
        let addToHome = app.buttons["pwaCatalog.addToHome"]
        XCTAssertTrue(addToHome.exists)
        XCTAssertTrue(addToHome.isEnabled)
        addToHome.tap()

        let back = app.buttons["pwaCatalog.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["pwaHome.app.dev.drel.data-template"]
                .waitForExistence(timeout: 8),
            "Adding a catalog app should make its Home tile visible"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "signed-app-catalog-added-to-home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSignedCatalogOpensAppWithoutAddingToHome() {
        let app = launchCatalog()

        let dataTemplate = app.buttons["pwaCatalog.app.dev.drel.data-template"]
        XCTAssertTrue(dataTemplate.waitForExistence(timeout: 20))
        dataTemplate.tap()

        let open = app.buttons["pwaCatalog.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        XCTAssertTrue(
            app.otherElements["browserManager.container"].waitForExistence(timeout: 15),
            "Opening from the catalog should launch the signed app"
        )
        XCTAssertTrue(app.webViews.firstMatch.exists)

        let nativeExit = app.descendants(matching: .any)["browserManager.immersiveReturnButton"]
        XCTAssertTrue(nativeExit.waitForExistence(timeout: 4))
        let collapsedFrame = nativeExit.frame
        nativeExit.tap()
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        ).withOffset(
            CGVector(dx: collapsedFrame.minX + 96, dy: collapsedFrame.midY)
        ).tap()

        XCTAssertTrue(
            app.buttons["pwaCatalog.app.dev.drel.data-template"].waitForExistence(timeout: 8),
            "Closing a catalog-launched web app should return to the catalog list"
        )
        let catalogBack = app.buttons["pwaCatalog.back"]
        XCTAssertTrue(catalogBack.waitForExistence(timeout: 4))

        catalogBack.tap()
        XCTAssertTrue(
            app.buttons["pwaHome.manageApps"].waitForExistence(timeout: 5),
            "The catalog must expose a working route back to My Apps"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "signed-app-catalog-returned-to-my-apps"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchCatalog() -> XCUIApplication {
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
        return app
    }
}
