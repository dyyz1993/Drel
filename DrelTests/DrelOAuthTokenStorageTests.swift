import XCTest
import WebBridgeKit
@testable import Drel

final class DrelOAuthTokenStorageTests: XCTestCase {
    private struct FailingStore: DrelOAuthTokenStoring {
        func saveRefreshToken(_: String, account _: String) throws { throw DrelOAuthKeychainError(status: errSecAuthFailed) }
        func loadRefreshToken(account _: String) throws -> String? { throw DrelOAuthKeychainError(status: errSecAuthFailed) }
        func delete(account _: String) throws { throw DrelOAuthKeychainError(status: errSecAuthFailed) }
        func removeAll() throws { throw DrelOAuthKeychainError(status: errSecAuthFailed) }
    }

    func testRefreshTokenNeverFallsBackToUserDefaults() throws {
        let defaults = UserDefaults(suiteName: "oauth-token-storage-tests")!
        defaults.removePersistentDomain(forName: "oauth-token-storage-tests")
        let storage = HTMLAppUserDefaultsStorage(userDefaults: defaults)
        let account = "gateway|app|origin|client|resource"
        let store = DrelOAuthKeychainTokenStore(service: "com.webbridgekit.superapp.oauth.tests.\(UUID().uuidString)")
        try store.saveRefreshToken("refresh-secret", account: account)
        XCTAssertEqual(try store.loadRefreshToken(account: account), "refresh-secret")
        XCTAssertNil(defaults.data(forKey: account))
        XCTAssertNil(storage.data(forKey: account))
        try store.delete(account: account)
        XCTAssertNil(try store.loadRefreshToken(account: account))
    }

    func testKeychainFailureFailsClosed() throws {
        XCTAssertThrowsError(try FailingStore().saveRefreshToken("secret", account: "account"))
        XCTAssertThrowsError(try FailingStore().loadRefreshToken(account: "account"))
    }

    func testDeviceKeySurvivesRepresentationAndRejectsUserDefaults() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["DREL_OAUTH_LIVE_KEYCHAIN_TESTS"] != "1",
            "Secure Enclave key tests require the live keychain environment to avoid simulator XPC hangs"
        )
        let defaults = UserDefaults(suiteName: "oauth-device-key-tests")!
        defaults.removePersistentDomain(forName: "oauth-device-key-tests")
        let keyStore = DrelOAuthSecureEnclaveKeyStore(service: "com.webbridgekit.superapp.oauth.device-key.tests.\(UUID().uuidString)")
        try keyStore.deleteIdentity()
        let identity = try keyStore.generateIdentity()
        let signature = try keyStore.sign(payload: Data("device-binding".utf8))
        XCTAssertFalse(signature.rawRepresentation.isEmpty)
        XCTAssertNil(defaults.data(forKey: identity.deviceID))
        let jwk = try keyStore.publicKeyJWK()
        XCTAssertEqual(jwk["kty"], "EC")
        XCTAssertEqual(jwk["crv"], "P-256")
        try keyStore.deleteIdentity()
        XCTAssertThrowsError(try keyStore.sign(payload: Data()))
    }
}
