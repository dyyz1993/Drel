import XCTest
@testable import Drel

final class DrelOAuthManifestValidationTests: XCTestCase {
    private struct RawManifest: Codable {
        let appId: String
        let startURL: String
        let allowedOrigins: [String]
        let authorization: DrelOAuthManifestAuthorization
    }

    private func manifest(
        clientID: String = "app.vot.example.invalid",
        baseURL: String = "https://vot.example.invalid:8443",
        prefix: String = "/api/",
        scopes: [String] = ["workspace.read", "bots.read"]
    ) -> DrelOAuthManifestAuthorization {
        .init(
            schemaVersion: "1",
            provider: "drel-oauth-pkce-v1",
            clientId: clientID,
            authorizationBaseURL: "https://api.drel.app",
            resource: .init(baseURL: baseURL, pathPrefix: prefix),
            scopes: scopes,
            refreshPolicy: .init(idleTimeoutSeconds: 100, absoluteLifetimeSeconds: 200, rotateOnRefresh: true)
        )
    }

    func testAcceptsExactContractManifest() throws {
        let result = try DrelOAuthManifestValidator.validate(
            authorization: manifest(),
            startURL: "https://vot.example.invalid:8443/",
            allowedOrigins: ["https://vot.example.invalid:8443"],
            trustedAppID: "app.vot.example.invalid"
        )
        XCTAssertEqual(result.resourceOrigin, "https://vot.example.invalid:8443")
        XCTAssertEqual(result.authorizationOrigin, "https://api.drel.app")
        XCTAssertEqual(result.scopes.count, 2)
    }

    func testRejectsWrongAppClientProviderForbiddenScopeAndPrefix() {
        let origins = ["https://vot.example.invalid:8443"]
        let appID = "app.vot.example.invalid"
        let startURL = "https://vot.example.invalid:8443/"
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(), startURL: startURL, allowedOrigins: origins, trustedAppID: "other.app"))
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(clientID: "other"), startURL: startURL, allowedOrigins: origins, trustedAppID: appID))
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(prefix: "/api"), startURL: startURL, allowedOrigins: origins, trustedAppID: appID))
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(scopes: ["admin"]), startURL: startURL, allowedOrigins: origins, trustedAppID: appID))
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(), startURL: startURL, allowedOrigins: ["https://other.example"], trustedAppID: appID))
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(authorization: manifest(), startURL: startURL, allowedOrigins: [], trustedAppID: appID))
    }

    func testFetchPathEnforcement() throws {
        let result = try DrelOAuthManifestValidator.validate(
            authorization: manifest(),
            startURL: "https://vot.example.invalid:8443/",
            allowedOrigins: ["https://vot.example.invalid:8443"],
            trustedAppID: "app.vot.example.invalid"
        )
        XCTAssertTrue(DrelOAuthManifestValidator.isAuthorizedPath("/api/config", manifest: result))
        for path in ["/config", "/api//x", "/api/../config", "/api/x?token=1", "/api/x#y", "//evil"] {
            XCTAssertFalse(DrelOAuthManifestValidator.isAuthorizedPath(path, manifest: result), path)
        }
    }

    func testRawManifestRequiresTrustedAppIDAndAuthorization() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let raw = try encoder.encode(
            RawManifest(
                appId: "app.vot.example.invalid",
                startURL: "https://vot.example.invalid:8443/",
                allowedOrigins: ["https://vot.example.invalid:8443"],
                authorization: manifest()
            )
        )
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(
            rawManifestData: raw,
            allowedOrigins: ["https://vot.example.invalid:8443"],
            trustedAppID: "other"
        ))
        let noAuth = try JSONEncoder().encode(["appId": "app.vot.example.invalid"])
        XCTAssertThrowsError(try DrelOAuthManifestValidator.validate(
            rawManifestData: noAuth,
            allowedOrigins: ["https://vot.example.invalid:8443"],
            trustedAppID: "app.vot.example.invalid"
        ))
    }
}
