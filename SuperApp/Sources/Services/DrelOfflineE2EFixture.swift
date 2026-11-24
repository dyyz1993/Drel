#if DEBUG
import CryptoKit
import Foundation
import WebBridgeKit

/// XCUITest-only fixture bootstrap (DEBUG builds only; compiled out of
/// release builds). Activated by the launch environment E2E_VOT_FIXTURE_DATA
/// pointing at the packaged VOT04104.dat container. It exercises the real
/// stale-package cold-start chain end to end without touching host
/// networking:
/// - installs the real VOT 0.4.10.4 static bundle through the real
///   HTMLAppOfflinePackageInstaller over an in-memory transport,
/// - embeds the signed parent manifest (0.4.10.4, test key) so the verified
///   stale-package fallback has its persisted trust anchor,
/// - registers the NEWER signed manifest (0.4.10.5) as gateway current,
///   which is exactly the stale-package regression scenario,
/// - activates the app so the real home tile appears,
/// - arms the DEBUG overrides: confirmed offline policy + fixture verifier,
/// - injects a DEBUG bootstrap user script into the browser main frame that
///   points the page's API base at an unreachable loopback port, so page API
///   failures happen without modifying device networking.
enum DrelOfflineE2EFixture {
    static let appID = "app.example.invalid"
    static let origin = URL(string: "https://api.example.invalid:8443")!
    static let installedVersion = "0.4.10.4"
    static let staleCurrentVersion = "0.4.10.5"
    /// SHA-256 of the pinned package.json manifest bytes (current 0.4.10.4
    /// build). Bootstrap fails closed if the fixture ever drifts.
    static let fixtureManifestSHA256 =
        "e7ced427de267505b52c13ec2fa4e220896d394d2d1fa3e450fb784c5550d0ba"
    private static let keyID = "gw-e2e-fixture"

    /// Fixed deterministic test-only signing key (derived from a constant
    /// seed; never used for production gateways).
    private static let signingKey: Curve25519.Signing.PrivateKey = {
        let seed = SHA256.hash(data: Data("drel-e2e-vot-fixture-signing-seed".utf8))
        return try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(seed))
    }()

    static func bootstrapIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard let containerPath = env["E2E_VOT_FIXTURE_DATA"],
              FileManager.default.fileExists(atPath: containerPath) else { return }
        DrelHTMLAppLaunchSupport.signatureVerifierOverride = fixtureVerifier
        DrelHTMLAppLaunchSupport.isConfirmedOfflineOverride = true
        HTMLAppOfflineFallbackRuntime.debugBootstrapUserScript = bootstrapScript
        do {
            try installFixtureSync(containerPath: containerPath)
            StructuredLogger.shared.info(
                "[E2EFixture] VOT fixture installed (installed 0.4.10.4 vs current 0.4.10.5)",
                category: .cache
            )
        } catch {
            StructuredLogger.shared.warning(
                "[E2EFixture] fixture install failed: \(error.localizedDescription)",
                category: .cache
            )
            assertionFailure("E2E fixture install failed: \(error)")
        }
    }

    private static var fixtureVerifier: ((HTMLAppManifest) -> Bool)? {
        HTMLAppGatewayOnboardingService.offlineFallbackSignatureVerifier(
            publicKeyID: keyID,
            publicKey: base64URL(signingKey.publicKey.rawRepresentation)
        )
    }

    /// Injected at document start into the app's browser main frame only:
    /// the page talks to an unreachable loopback API base and carries a saved
    /// token, reproducing the offline retry UI deterministically.
    private static var bootstrapScript: String {
        """
        try { localStorage.setItem('vot-token', 'e2e-saved-token'); } catch (e) {}
        try {
          Object.defineProperty(window, 'VOT_PUBLIC_BASE', {
            get: function () { return 'http://127.0.0.1:9'; },
            configurable: false
          });
        } catch (e) {}
        """
    }

    // MARK: - Container parsing (same container format as the unit E2E test)

    private struct FixtureContainer {
        let files: [String: Data]

        init(data: Data) throws {
            var files: [String: Data] = [:]
            var offset = 0
            func take(_ length: Int) throws -> Data {
                guard offset + length <= data.count else {
                    throw URLError(.cannotDecodeContentData)
                }
                let slice = data.subdata(in: offset..<(offset + length))
                offset += length
                return slice
            }
            let count = try take(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            for _ in 0..<count {
                let nameLength = Int(try take(2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                let name = String(data: try take(nameLength), encoding: .utf8) ?? ""
                let size = Int(try take(8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian })
                files[name] = try take(size)
            }
            self.files = files
        }

        func file(_ name: String) throws -> Data {
            guard let data = files[name] else { throw URLError(.cannotOpenFile) }
            return data
        }
    }

    private actor MemoryTransport: HTMLAppPackageTransport {
        let responses: [URL: HTMLAppPackageTransportResponse]

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

    /// Synchronous install so the cold start has the package, the registry
    /// entry and the activation ready before the first frame renders.
    private static func installFixtureSync(containerPath: String) throws {
        let container = try FixtureContainer(
            data: try Data(contentsOf: URL(fileURLWithPath: containerPath))
        )
        let manifestData = try container.file("package.json")
        let digest = sha256Hex(manifestData)
        guard digest == fixtureManifestSHA256 else {
            throw URLError(.cannotDecodeContentData)
        }
        let package = try JSONDecoder().decode(HTMLAppOfflinePackageManifest.self, from: manifestData)

        var responses: [URL: HTMLAppPackageTransportResponse] = [:]
        let manifestURL = origin.appendingPathComponent("drel/v\(installedVersion)/package.json")
        responses[manifestURL] = .init(data: manifestData, finalURL: manifestURL)
        for file in package.files {
            guard let url = URL(string: file.url) else { throw URLError(.badURL) }
            responses[url] = .init(data: try container.file(file.path), finalURL: url)
        }

        let installer = HTMLAppOfflinePackageInstaller(transport: MemoryTransport(responses: responses))
        let installedParent = try makeSignedParent(version: installedVersion, digest: fixtureManifestSHA256)
        let staleCurrent = try makeSignedParent(
            version: staleCurrentVersion,
            digest: String(repeating: "c", count: 64)
        )

        var installError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do {
                let installed = try await installer.install(appManifest: installedParent)
                if installed.resourceManifestSHA256 != fixtureManifestSHA256 {
                    installError = URLError(.cannotDecodeContentData)
                }
            } catch {
                installError = error
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            throw URLError(.timedOut)
        }
        if let installError {
            throw installError
        }
        // The gateway current manifest is the STALE trigger; activation makes
        // the real home tile visible.
        try HTMLAppRuntimeCenter.shared.trustRegistry.register(staleCurrent)
        HTMLAppPushActivationStore().activate(appID)
    }

    private static func makeSignedParent(version: String, digest: String) throws -> HTMLAppManifest {
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

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
