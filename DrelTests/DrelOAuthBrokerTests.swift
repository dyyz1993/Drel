import CryptoKit
import XCTest
@testable import Drel
import WebBridgeKit

final class DrelOAuthBrokerTests: XCTestCase {
    private let appID = "app.example.invalid"
    private let origin = "https://api.example.invalid:8443"
    private let gatewayKey = "test-gateway-key"
    private let storageKey = "com.webbridgekit.superapp.oauth.manifest-authorizations"

    private func manifest() -> DrelOAuthManifestAuthorization {
        .init(
            schemaVersion: "1",
            provider: "drel-device-grant-v1",
            clientId: appID,
            resource: .init(baseURL: origin, pathPrefix: "/api/"),
            scopes: ["workspace.read", "bots.read"],
            refreshPolicy: .init(idleTimeoutSeconds: 100, absoluteLifetimeSeconds: 200, rotateOnRefresh: true)
        )
    }

    private func trustedManifest() -> HTMLAppManifest {
        HTMLAppManifest(
            appID: appID,
            name: "VOT",
            startURL: origin + "/",
            allowedOrigins: [origin],
            capabilities: [],
            routes: ["/"],
            cache: HTMLAppCachePolicy(strategy: .networkOnly, version: "oauth-test", persistent: false)
        )
    }

    private func grant(expiresIn: TimeInterval = 300, refreshToken: String = "refresh-1") -> DrelOAuthGrant {
        let now = Date()
        return .init(
            contextKey: "gateway|\(appID)|\(origin)|\(appID)|\(origin)",
            gatewayIdentity: "gateway",
            appID: appID,
            documentOrigin: origin,
            clientID: appID,
            resourceOrigin: origin,
            grantID: "grant",
            scope: try! DrelOAuthScope.set(["workspace.read", "bots.read"]),
            accessToken: "access",
            refreshToken: refreshToken,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: now.addingTimeInterval(1000),
            lastRefreshedAt: now
        )
    }

    private func makeBroker(
        result: @escaping @Sendable (URLRequest) async throws -> (Data, Int)
    ) throws -> DrelOAuthBroker {
        let registry = HTMLAppTrustRegistry(storage: InMemoryStorage())
        let trusted = trustedManifest()
        try registry.register(trusted)

        let authorizationData = try JSONEncoder().encode(manifest())
        let snapshot = DrelOAuthAuthorizationSnapshot(
            appID: appID,
            authorization: authorizationData,
            manifestFingerprint: DrelOAuthGatewayAuthorizationIntegration.fingerprint(trusted)
        )
        let state = DrelOAuthAuthorizationSnapshotState(
            gateways: [gatewayKey: [appID: snapshot]]
        )
        let storage = InMemoryStorage(initial: [
            storageKey: try JSONEncoder().encode(state)
        ])

        return DrelOAuthBroker(
            trustRegistry: registry,
            storage: storage,
            authorizationGatewayKey: gatewayKey,
            keyStore: MockKeyStore(),
            tokenStore: InMemorySecureTokenStore(),
            httpClient: MockHTTPClient(result: result),
            consentPresenter: MockConsent(allowed: true),
            now: { Date(timeIntervalSince1970: 1000) }
        )
    }

    func testScopeRequestCannotExceedSignedManifest() async throws {
        let broker = try makeBroker { _ in (Data(), 200) }
        do {
            _ = try await broker.authorizationRequest(
                scopes: ["workspace.read", "admin"],
                gatewayIdentity: "gateway",
                appID: appID,
                documentOrigin: origin,
                pairingRequestID: nil
            )
            XCTFail("Scope outside the signed manifest must fail closed")
        } catch let error as DrelOAuthError {
            XCTAssertEqual(error, .scopeExceeded)
        }
    }

    func testConcurrentRefreshSharesOneFlightAndRotatesToken() async throws {
        let counter = Counter()
        let response = grantResponse(refreshToken: "refresh-2")
        let broker = try makeBroker { request in
            guard request.url?.path == "/api/v1/auth/drel/refresh" else {
                return (Data(), 404)
            }
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return (response, 200)
        }
        let stale = grant(expiresIn: -10)

        async let first = broker.refresh(grant: stale)
        async let second = broker.refresh(grant: stale)
        let results = try await [first, second]

        XCTAssertEqual(Set(results.map(\.refreshToken)), ["refresh-2"])
        let refreshCount = await counter.value
        XCTAssertEqual(refreshCount, 1)
        try DrelOAuthKeychainStore().delete(account: stale.contextKey)
    }

    func testRevocationClearsRefreshTokenAndGrantMetadata() async throws {
        let broker = try makeBroker { request in
            request.url?.path == "/api/v1/auth/drel/revoke" ? (Data(), 204) : (Data(), 404)
        }
        let grant = grant()
        try broker.storeGrantForTesting(grant)

        try await broker.revoke(
            gatewayIdentity: "gateway",
            appID: appID,
            documentOrigin: origin
        )

        let status = try broker.status(
            gatewayIdentity: "gateway",
            appID: appID,
            documentOrigin: origin
        )
        XCTAssertEqual(status.status, "consent_required")
        XCTAssertNil(try DrelOAuthKeychainGrantMetadataStore().load(contextKey: grant.contextKey))
    }

    private func grantResponse(refreshToken: String) -> Data {
        let object: [String: Any] = [
            "grantId": "rotated-grant",
            "scope": "bots.read workspace.read",
            "accessToken": "rotated-access",
            "tokenType": "DPoP",
            "expiresIn": 300,
            "refreshToken": refreshToken,
            "refreshExpiresIn": 1000
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    private final class InMemoryStorage: HTMLAppRuntimeStorage {
        private var values: [String: Data]
        init(initial: [String: Data] = [:]) { values = initial }
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data?, forKey key: String) { values[key] = data }
    }

    private struct MockHTTPClient: DrelOAuthHTTPClient {
        let result: @Sendable (URLRequest) async throws -> (Data, Int)

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (data, status) = try await result(request)
            return (
                data,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
    }

    private struct MockKeyStore: DrelOAuthDeviceKeyStoring {
        private let key = P256.Signing.PrivateKey()

        func currentIdentity() throws -> DrelOAuthDeviceIdentity? {
            .init(deviceID: "device", usesSecureEnclave: false)
        }

        func generateIdentity() throws -> DrelOAuthDeviceIdentity {
            .init(deviceID: "device", usesSecureEnclave: false)
        }

        func sign(payload: Data) throws -> P256.Signing.ECDSASignature {
            try key.signature(for: payload)
        }

        func publicKeyJWK() throws -> [String: String] {
            ["kty": "EC", "crv": "P-256", "x": "x", "y": "y"]
        }

        func deleteIdentity() throws {}
    }

    private final class InMemorySecureTokenStore: DrelOAuthTokenStoring {
        private var tokens: [String: String] = [:]

        func saveRefreshToken(_ token: String, account: String) throws {
            tokens[account] = token
        }

        func loadRefreshToken(account: String) throws -> String? {
            tokens[account]
        }

        func delete(account: String) throws {
            tokens.removeValue(forKey: account)
        }

        func removeAll() throws {
            tokens.removeAll()
        }
    }

    private struct MockConsent: DrelOAuthConsentPresenting {
        let allowed: Bool

        @MainActor
        func request(
            appName _: String,
            resourceOrigin _: String,
            scopes _: [String],
            completion: @escaping (Bool) -> Void
        ) {
            completion(allowed)
        }
    }
}
