import CryptoKit
import WebKit
import XCTest
@testable import Drel
import WebBridgeKit

/// Simulator-isolated end-to-end coverage for the offline stale-package
/// fallback on the real VOT 0.4.10.4 static bundle (copied verbatim into the
/// test bundle, hashes pinned below). The injected gateway base URL is an
/// unreachable loopback port, so API failures happen without touching device
/// networking.
@MainActor
final class HTMLAppOfflineEndToEndTests: XCTestCase {
    /// SHA-256 of the bundled package.json manifest bytes (current 0.4.10.4
    /// build). The test fails if the fixture ever drifts from this build.
    private static let fixtureResourceManifestSHA256 =
        "e7ced427de267505b52c13ec2fa4e220896d394d2d1fa3e450fb784c5550d0ba"
    /// SHA-256 of the bundled drel.html entrypoint (same pinned build).
    private static let fixtureDrelHTMLSHA256 =
        "fd70f288e7aac95655fc391f80624197767fd27a25d4646755c39925da4cb3cc"

    private final class MemoryStorage: HTMLAppRuntimeStorage {
        var values: [String: Data] = [:]
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data?, forKey key: String) { values[key] = data }
    }

    private actor MemoryTransport: HTMLAppPackageTransport {
        var responses: [URL: HTMLAppPackageTransportResponse]
        init(responses: [URL: HTMLAppPackageTransportResponse]) {
            self.responses = responses
        }
        func data(from url: URL, maximumBytes: Int) async throws -> HTMLAppPackageTransportResponse {
            guard let response = responses[url] else {
                throw URLError(.notConnectedToInternet)
            }
            guard response.data.count <= maximumBytes else {
                throw HTMLAppOfflinePackageError.resourceManifestTooLarge
            }
            return response
        }
    }

    private final class NavigationRecorder: NSObject, WKNavigationDelegate {
        var nonFileProvisionalURLs: [URL] = []
        private var continuation: CheckedContinuation<Void, Never>?

        func waitForDidFinish() async {
            await withCheckedContinuation { cont in
                continuation = cont
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url, !url.isFileURL {
                nonFileProvisionalURLs.append(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume()
            continuation = nil
        }
    }

    private let origin = URL(string: "https://api.example.invalid:8443")!
    private let appID = "app.example.invalid"
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let keyID = "gw-e2e-key"
    private let locator = HTMLAppOfflinePackageLocator()

    override func setUp() async throws {
        try await super.setUp()
        DrelOfflineDiagnostics.shared.clear()
        DrelHTMLAppLaunchSupport.isConfirmedOfflineOverride = nil
        DrelHTMLAppLaunchSupport.signatureVerifierOverride = gatewayVerifier()
    }

    override func tearDown() async throws {
        try? locator.removeInstalledPackage(appID: appID)
        HTMLAppOfflineFallbackRuntime.signatureVerifier = nil
        HTMLAppOfflineFallbackRuntime.isOfflineProvider = nil
        DrelHTMLAppLaunchSupport.isConfirmedOfflineOverride = nil
        DrelHTMLAppLaunchSupport.signatureVerifierOverride = nil
        DrelOfflineDiagnostics.shared.clear()
        try await super.tearDown()
    }

    private func gatewayVerifier() -> ((HTMLAppManifest) -> Bool)? {
        HTMLAppGatewayOnboardingService.offlineFallbackSignatureVerifier(
            publicKeyID: keyID,
            publicKey: base64URL(signingKey.publicKey.rawRepresentation)
        )
    }

    // MARK: - Current-version cold start

    func testOfflineColdStartRendersRealVOTBundleAndKeepsDiagnosticsOffline() async throws {
        let parent = try makeSignedParent(version: "0.4.10.4", digest: Self.fixtureResourceManifestSHA256)
        let installed = try await installCurrentVOTBundle(parent: parent)
        let registry = makeRegistry(current: parent)
        let resolver = DrelHTMLAppLaunchSupport.makeResolver(trustRegistry: registry)

        let target = try resolver.resolve(
            appID: appID,
            route: "/drel.html",
            networkPolicy: .offlineFallback
        )
        XCTAssertEqual(target.offlineMode, .strong)
        XCTAssertTrue(target.loaderURL.isFileURL)
        let entryBytes = try Data(contentsOf: target.loaderURL)
        XCTAssertEqual(sha256(entryBytes), Self.fixtureDrelHTMLSHA256)

        let diagnostics = OfflineAppDiagnosticsCoordinator.begin(manifest: parent, source: "e2e")
        DrelOfflineDiagnostics.shared.record(
            attemptID: diagnostics.attemptID,
            phase: .launch,
            status: .succeeded,
            loadSource: .offlinePackage,
            outcome: "resolved"
        )
        let attempt = try XCTUnwrap(DrelOfflineDiagnostics.shared.attempts(appID: appID).last)
        let packageEvent = try XCTUnwrap(attempt.events.last { $0.phase == .package })
        XCTAssertEqual(packageEvent.status, .succeeded)
        XCTAssertEqual(packageEvent.loadSource, .offlinePackage)
        XCTAssertEqual(packageEvent.outcome, "packageFound")
        XCTAssertEqual(attempt.currentLoadSource, .offlinePackage)

        let (webView, _) = makeWebView()
        try await load(webView, url: target.loaderURL)
        let version = try await waitFor(webView, "window.VOT_OFFLINE_PACKAGE")
        XCTAssertEqual(version, "0.4.10.4")
        let title = try await waitFor(webView, "document.title")
        XCTAssertEqual(title, "VOT · 我的机器人")
        let savedToken = try await waitFor(webView, "localStorage.getItem('vot-token')")
        XCTAssertEqual(savedToken, "e2e-saved-token")
        let loginError = try await waitFor(
            webView,
            "document.getElementById('loginError').textContent"
        )
        XCTAssertEqual(loginError, "无法连接工作台，请检查网络后重新连接。")
        let retryVisibility = try await waitFor(
            webView,
            "document.getElementById('retryConnection').classList.contains('hidden') ? 'hidden' : 'visible'"
        )
        XCTAssertEqual(retryVisibility, "visible")
        XCTAssertTrue(webViewNavigationRecorderFor(webView).nonFileProvisionalURLs.isEmpty)
    }

    // MARK: - Newer manifest while offline

    func testNewerManifestOfflineFallbackServesVerifiedStaleBundle() async throws {
        let parent = try makeSignedParent(version: "0.4.10.4", digest: Self.fixtureResourceManifestSHA256)
        let installed = try await installCurrentVOTBundle(parent: parent)
        let updated = try makeSignedParent(version: "0.4.10.5", digest: String(repeating: "c", count: 64))
        let registry = makeRegistry(current: updated)
        let resolver = DrelHTMLAppLaunchSupport.makeResolver(trustRegistry: registry)
        DrelHTMLAppLaunchSupport.isConfirmedOfflineOverride = true

        let target = try resolver.resolve(
            appID: appID,
            route: "/drel.html",
            networkPolicy: .offlineFallback
        )
        XCTAssertEqual(target.offlineMode, .strong)
        XCTAssertTrue(target.loaderURL.isFileURL)
        XCTAssertTrue(
            target.loaderURL.deletingLastPathComponent().path == installed.directoryURL.path
        )

        let diagnostics = OfflineAppDiagnosticsCoordinator.begin(manifest: updated, source: "e2e")
        let attempt = try XCTUnwrap(DrelOfflineDiagnostics.shared.attempts(appID: appID).last)
        let packageEvent = try XCTUnwrap(attempt.events.last { $0.phase == .package })
        XCTAssertEqual(packageEvent.status, .succeeded)
        XCTAssertEqual(packageEvent.loadSource, .offlinePackage)
        XCTAssertEqual(packageEvent.outcome, "staleFallbackVerified")

        let (webView, _) = makeWebView()
        try await load(webView, url: target.loaderURL)
        let version = try await waitFor(webView, "window.VOT_OFFLINE_PACKAGE")
        XCTAssertEqual(version, "0.4.10.4")
        let loginError = try await waitFor(
            webView,
            "document.getElementById('loginError').textContent"
        )
        XCTAssertEqual(loginError, "无法连接工作台，请检查网络后重新连接。")
    }

    // MARK: - Online policy stays on the network page

    func testOnlinePolicyKeepsNetworkPageAndReportsVersionMismatch() async throws {
        let parent = try makeSignedParent(version: "0.4.10.4", digest: Self.fixtureResourceManifestSHA256)
        _ = try await installCurrentVOTBundle(parent: parent)
        let updated = try makeSignedParent(version: "0.4.10.5", digest: String(repeating: "c", count: 64))
        let registry = makeRegistry(current: updated)
        let resolver = DrelHTMLAppLaunchSupport.makeResolver(trustRegistry: registry)

        let target = try resolver.resolve(appID: appID, route: "/drel.html")
        XCTAssertEqual(target.offlineMode, .partial)
        XCTAssertNil(target.installedPackageURL)
        XCTAssertEqual(target.loaderURL, origin.appendingPathComponent("drel.html"))

        let diagnostics = OfflineAppDiagnosticsCoordinator.begin(manifest: updated, source: "e2e")
        let attempt = try XCTUnwrap(DrelOfflineDiagnostics.shared.attempts(appID: appID).last)
        let packageEvent = try XCTUnwrap(attempt.events.last { $0.phase == .package })
        XCTAssertEqual(packageEvent.status, .failed)
        XCTAssertEqual(packageEvent.loadSource, .online)
        XCTAssertEqual(packageEvent.outcome, "versionMismatch")
    }

    // MARK: - Fixtures

    private struct InstalledFixture {
        var installed: InstalledHTMLAppPackage
        var directoryURL: URL
    }

    /// Parses the packaged fixture container (VOT04104.dat). The container
    /// format bypasses the Xcode resource pipeline entirely, so every file
    /// byte reaches the installer exactly as produced by the real build.
    private lazy var fixtureFiles: [String: Data] = {
        guard let url = Bundle(for: Self.self).url(
            forResource: "VOT04104", withExtension: "dat"
        ) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { return [:] }
        var files: [String: Data] = [:]
        var offset = 0
        func take(_ length: Int) -> Data {
            let slice = data.subdata(in: offset..<(offset + length))
            offset += length
            return slice
        }
        let count = take(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        for _ in 0..<count {
            let nameLength = Int(take(2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            let name = String(data: take(nameLength), encoding: .utf8) ?? ""
            let size = Int(take(8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
            files[name] = take(size)
        }
        return files
    }()

    private func bundleFile(_ name: String) throws -> Data {
        guard let data = fixtureFiles[name] else {
            throw URLError(.cannotOpenFile)
        }
        return data
    }

    private func installCurrentVOTBundle(parent: HTMLAppManifest) async throws -> InstalledFixture {
        let manifestData = try bundleFile("package.json")
        let digest = sha256(manifestData)
        XCTAssertEqual(digest, Self.fixtureResourceManifestSHA256)
        let package = try JSONDecoder().decode(HTMLAppOfflinePackageManifest.self, from: manifestData)

        var responses: [URL: HTMLAppPackageTransportResponse] = [:]
        let manifestURL = origin.appendingPathComponent("drel/v0.4.10.4/package.json")
        responses[manifestURL] = .init(data: manifestData, finalURL: manifestURL)
        for file in package.files {
            let url = try XCTUnwrap(URL(string: file.url))
            responses[url] = .init(data: try bundleFile(file.path), finalURL: url)
        }

        let installer = HTMLAppOfflinePackageInstaller(
            transport: MemoryTransport(responses: responses)
        )
        let installed = try await installer.install(appManifest: parent)
        XCTAssertEqual(installed.resourceManifestSHA256, Self.fixtureResourceManifestSHA256)
        let appRoot = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("WebBridgeKit/Packages", isDirectory: true)
        let directoryURL = appRoot
            .appendingPathComponent(sha256Hex(appID))
            .appendingPathComponent("versions/\(installed.directoryName)", isDirectory: true)
        return InstalledFixture(installed: installed, directoryURL: directoryURL)
    }

    private func makeRegistry(current: HTMLAppManifest) -> HTMLAppTrustRegistry {
        let registry = HTMLAppTrustRegistry(storage: MemoryStorage())
        try? registry.register(current)
        return registry
    }

    private func makeSignedParent(version: String, digest: String) throws -> HTMLAppManifest {
        let unsigned = HTMLAppManifest(
            appID: appID,
            name: "VOT",
            startURL: origin.appendingPathComponent("drel.html").absoluteString,
            allowedOrigins: [origin.absoluteString],
            capabilities: [],
            routes: ["/", "/index.html", "/drel.html"],
            cache: HTMLAppCachePolicy(
                strategy: .manifest,
                version: version,
                persistent: true,
                resourceManifestURL: origin
                    .appendingPathComponent("drel/v\(version)/package.json").absoluteString,
                resourceManifestSHA256: digest
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(unsigned)
        let signatureData = try signingKey.signature(for: payload)
        return HTMLAppManifest(
            appID: unsigned.appID,
            name: unsigned.name,
            startURL: unsigned.startURL,
            allowedOrigins: unsigned.allowedOrigins,
            capabilities: unsigned.capabilities,
            routes: unsigned.routes,
            cache: unsigned.cache,
            signature: HTMLAppManifestSignature(
                algorithm: "ed25519",
                keyID: keyID,
                value: base64URL(signatureData)
            )
        )
    }

    // MARK: - WKWebView harness

    private func makeWebView() -> (WKWebView, NavigationRecorder) {
        let configuration = WKWebViewConfiguration()
        let bootstrap = """
        try { localStorage.setItem('vot-token', 'e2e-saved-token'); } catch (e) {}
        try {
          Object.defineProperty(window, 'VOT_PUBLIC_BASE', {
            get: function () { return 'http://127.0.0.1:9'; },
            configurable: false
          });
        } catch (e) {}
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        let recorder = NavigationRecorder()
        webView.navigationDelegate = recorder
        recorderByObject[ObjectIdentifier(webView)] = recorder
        return (webView, recorder)
    }

    private var recorderByObject: [ObjectIdentifier: NavigationRecorder] = [:]

    private func webViewNavigationRecorderFor(_ webView: WKWebView) -> NavigationRecorder {
        recorderByObject[ObjectIdentifier(webView)] ?? NavigationRecorder()
    }

    private func load(_ webView: WKWebView, url: URL) async throws {
        let recorder = webViewNavigationRecorderFor(webView)
        _ = webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        await recorder.waitForDidFinish()
    }

    private func waitFor(_ webView: WKWebView, _ script: String) async throws -> String {
        let deadline = Date().addingTimeInterval(5)
        var last = ""
        while Date() < deadline {
            let result = try await evaluate(webView, script)
            last = result
            if result != "null" && !result.isEmpty { return result }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return last
    }

    private func evaluate(_ webView: WKWebView, _ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: String(describing: result))
                }
            }
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
