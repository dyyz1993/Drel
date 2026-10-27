import XCTest
import WebBridgeKit
@testable import Drel

final class PushExampleURLBuilderTests: XCTestCase {
    func testStoreExamplesBuildExactRequestURL() throws {
        let expectedIDs = [
            "bodyOnly", "plain", "markdown", "otp", "qr", "image",
            "sound", "badge", "badgeClear", "url", "copyManual", "copy",
            "replace", "recall"
        ]
        let base = "https://api.drel.app"
        let identity = "fixture_identity"

        for id in expectedIDs {
            let example = try XCTUnwrap(PushExample.example(id: id), "Missing example \(id)")
            let url = try XCTUnwrap(
                PushExample.requestURL(
                    id: example.id,
                    title: example.pushTitle,
                    body: example.pushBody,
                    queryItems: example.queryItems,
                    baseURL: base,
                    pushIdentity: identity
                )
            )
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "api.drel.app")
            XCTAssertTrue(url.path.contains(identity), "\(id) URL omitted push identity")
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let names = Set(items.map(\.name))
            for expected in example.queryItems {
                XCTAssertTrue(names.contains(expected.name), "\(id) URL omitted \(expected.name)")
            }
        }
    }

    func testTitleAndBodyArePercentEncodedPathSegments() throws {
        let url = try XCTUnwrap(PushExample.requestURL(
            id: "plain",
            title: "标题/测试",
            body: "正文?测试",
            queryItems: [],
            baseURL: "https://api.drel.app/",
            pushIdentity: "identity"
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedPath, "/identity/%E6%A0%87%E9%A2%98%2F%E6%B5%8B%E8%AF%95/%E6%AD%A3%E6%96%87%3F%E6%B5%8B%E8%AF%95")
        XCTAssertNil(components.queryItems)
    }
}

final class MessageDetailNavigationTests: XCTestCase {
    @MainActor
    func testIndicatorOrderPlacesPrevOnLeftAndNextOnRight() {
        let payload1 = MessagePayload(id: "msg-1", title: "Msg 1", body: "Body 1", channel: "official")
        let stored1 = StoredMessage(id: "msg-1", payload: payload1, isRead: false)
        let payload2 = MessagePayload(id: "msg-2", title: "Msg 2", body: "Body 2", channel: "official")
        let stored2 = StoredMessage(id: "msg-2", payload: payload2, isRead: false)

        let detailVC = MessageDetailViewController(message: stored1, peerMessages: [stored1, stored2])
        _ = detailVC.view

        let stackViews = detailVC.view.subviews.compactMap { $0 as? UIStackView }
        let navStack = stackViews.first { stack in
            stack.arrangedSubviews.contains { $0.accessibilityIdentifier == "message.detail.indicator.next" }
        }
        XCTAssertNotNil(navStack, "Side indicator stack must be present in view")
        let subviews = navStack?.arrangedSubviews ?? []
        XCTAssertEqual(subviews.count, 2)
        XCTAssertEqual(subviews[0].accessibilityIdentifier, "message.detail.indicator.prev", "Previous indicator must be on the left (index 0)")
        XCTAssertEqual(subviews[1].accessibilityIdentifier, "message.detail.indicator.next", "Next indicator must be on the right (index 1)")
    }

    func testEngineBootstrapDoesNotSetAutoRouteOnReceive() async {
        let engine = MessageEngine.shared
        let onRoute = await engine.onRoute
        XCTAssertNil(onRoute, "MessageEngine.onRoute must be nil so receiving pushes never auto-opens URLs")
    }
}
