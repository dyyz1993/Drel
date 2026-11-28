//
//  DrelAppOpenFallbackTests.swift
//  DrelTests
//

import XCTest
import WebBridgeKit
@testable import Drel

final class DrelAppOpenFallbackTests: XCTestCase {
    private func makeManifest(appID: String, startURL: String) -> HTMLAppManifest {
        HTMLAppManifest(
            appID: appID,
            name: "Fallback App",
            startURL: startURL,
            allowedOrigins: [],
            capabilities: [],
            routes: ["/"],
            cache: HTMLAppCachePolicy(strategy: .networkOnly, version: "fallback-test", persistent: false)
        )
    }

    func testDeriveStartURLAcceptsValidPublicHosts() {
        XCTAssertEqual(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.vot.19930810.xyz")?.absoluteString, "https://vot.19930810.xyz/")
        XCTAssertEqual(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.example.com")?.absoluteString, "https://example.com/")
        XCTAssertEqual(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.example.io")?.absoluteString, "https://example.io/")
        XCTAssertEqual(DrelAppOpenFallback.deriveStartURL(fromAppID: "APP.example.com")?.absoluteString, "https://example.com/")
    }

    func testDeriveStartURLRejectsInvalidHosts() {
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.singlelabel"))
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.dev.drel.example.com"))
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.com.webbridgekit.example"))
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "vot.19930810.xyz"))
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "APP.DEV.DREL.x"))
        XCTAssertNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.COM.WEBBRIDGEKIT.x"))
    }

    func testDeriveStartURLRejectsPrivateAndReservedHosts() {
        // Loopback, link-local (cloud metadata), RFC 1918, CGNAT, multicast,
        // .local mDNS and IPv6 literals must never become a fallback target.
        for appID in [
            "app.127.0.0.1", "app.169.254.169.254", "app.10.0.0.1", "app.192.168.1.1",
            "app.172.16.0.1", "app.172.31.255.254", "app.100.64.0.1", "app.224.0.0.1",
            "app.0.0.0.0", "app.printer.local", "app.localhost", "app.metadata.google.internal",
            "app.[::1]", "app.::1",
        ] {
            XCTAssertNil(
                DrelAppOpenFallback.deriveStartURL(fromAppID: appID),
                "\(appID) must not derive a fallback URL"
            )
        }
        // Public addresses stay allowed.
        XCTAssertNotNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.8.8.8.8"))
        XCTAssertNotNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.172.32.0.1"))
        XCTAssertNotNil(DrelAppOpenFallback.deriveStartURL(fromAppID: "app.100.63.0.1"))
    }

    func testDecideRejectsUserinfoAndPrivateURLsFromPayload() throws {
        let payload = PushPayload(userInfo: [
            "appId": "app.vot.19930810.xyz",
            "route": "/",
            "url": "https://vot.19930810.xyz@evil.example/steal",
            "title": "VOT",
        ])
        guard case .openInBrowser(let url, _) = DrelAppOpenFallback.decide(
            appID: "app.vot.19930810.xyz",
            route: "/",
            untrustedManifests: [],
            payload: payload
        ) else {
            return XCTFail("expected a browser fallback")
        }
        XCTAssertEqual(url.absoluteString, "https://vot.19930810.xyz/", "userinfo URL must be dropped, derivation wins")
        XCTAssertNil(DrelAppOpenFallback.trustedHTTPSURLForRegistration(from: "https://user:pw@example.com/"))
        XCTAssertNil(DrelAppOpenFallback.trustedHTTPSURLForRegistration(from: "https://127.0.0.1/"))
        XCTAssertNil(DrelAppOpenFallback.trustedHTTPSURLForRegistration(from: "http://example.com/"))
        XCTAssertNotNil(DrelAppOpenFallback.trustedHTTPSURLForRegistration(from: "https://example.com/path"))
    }

    func testDecidePrefersHTTPSURLFromPayload() {
        let payload = PushPayload(userInfo: [
            "appId": "app.vot.19930810.xyz",
            "route": "/",
            "url": "https://payload.example.com/start",
            "title": "Payload App"
        ])
        let decision = DrelAppOpenFallback.decide(
            appID: "app.vot.19930810.xyz",
            route: "/",
            untrustedManifests: [makeManifest(appID: "app.vot.19930810.xyz", startURL: "https://manifest.example.com/")],
            payload: payload
        )
        XCTAssertEqual(decision, .openInBrowser(URL(string: "https://payload.example.com/start")!, appName: "Payload App"))
    }

    func testDecidePrefersUntrustedManifestBeforeHostDerivation() {
        let decision = DrelAppOpenFallback.decide(
            appID: "app.vot.19930810.xyz",
            route: "/",
            untrustedManifests: [makeManifest(appID: "app.vot.19930810.xyz", startURL: "https://manifest.example.com/start")],
            payload: nil
        )
        XCTAssertEqual(decision, .openInBrowser(URL(string: "https://manifest.example.com/start")!, appName: "Fallback App"))
    }

    func testDecideDerivesStartURLWithoutUntrustedManifest() {
        let decision = DrelAppOpenFallback.decide(appID: "app.vot.19930810.xyz", route: "/", untrustedManifests: [], payload: nil)
        XCTAssertEqual(decision, .openInBrowser(URL(string: "https://vot.19930810.xyz/")!, appName: "app.vot.19930810.xyz"))
    }

    func testDecideDoesNotDeriveSelfHostedDevelopmentID() {
        let decision = DrelAppOpenFallback.decide(appID: "app.dev.drel.example.com", route: "/", untrustedManifests: [], payload: nil)
        XCTAssertEqual(decision, .cannotOpen(reason: .untrustedRoute(appID: "app.dev.drel.example.com")))
    }
}
