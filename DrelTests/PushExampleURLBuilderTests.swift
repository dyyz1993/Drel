import XCTest
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
