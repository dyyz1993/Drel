import XCTest

final class GatewayOnboardingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--UITesting", "-UITesting"]
    }

    func testGatewayScreenExposesOnePageImportAndExplicitActivation() {
        app.launchEnvironment["WBK_GATEWAY_UI_PAYLOAD"] = Self.localPayload
        app.launch()
        openGatewayManagement()

        XCTAssertTrue(element("gateway.current").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gateway.scan"].exists)
        XCTAssertTrue(app.buttons["gateway.paste"].exists)
        XCTAssertTrue(app.textViews["gateway.input"].exists)
        XCTAssertTrue(app.buttons["gateway.validate"].exists)
    }

    func testSecretPayloadShowsErrorAndNeverShowsActivation() {
        app.launchEnvironment["WBK_GATEWAY_UI_PAYLOAD"] = """
        {"name":"Unsafe","baseURL":"https://gateway.example.com","privateKey":"secret"}
        """
        app.launch()
        openGatewayManagement()
        app.buttons["gateway.validate"].tap()

        XCTAssertTrue(element("gateway.error").waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["gateway.activate"].exists)
    }

    private func openGatewayManagement() {
        let home = app.tabBars.buttons["tab.apps"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        let manage = app.buttons["pwaHome.manageApps"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        let serviceManagement = app.buttons["管理应用服务"]
        if serviceManagement.waitForExistence(timeout: 2) {
            serviceManagement.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "gateway.table")
            .firstMatch.waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private static let localPayload = """
    {
      "id": "local-ui",
      "name": "Local UI Gateway",
      "baseURL": "http://localhost:8080",
      "healthPath": "/health",
      "manifestPath": "/manifest"
    }
    """
}
