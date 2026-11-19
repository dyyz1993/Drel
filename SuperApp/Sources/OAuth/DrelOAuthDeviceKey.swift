import CryptoKit
import Foundation
import Security

public struct DrelOAuthDeviceIdentity: Codable, Equatable {
    public let deviceID: String
    public let usesSecureEnclave: Bool
}

public protocol DrelOAuthDeviceKeyStoring {
    func currentIdentity() throws -> DrelOAuthDeviceIdentity?
    func generateIdentity() throws -> DrelOAuthDeviceIdentity
    func sign(payload: Data) throws -> P256.Signing.ECDSASignature
    func publicKeyJWK() throws -> [String: String]
    func deleteIdentity() throws
}

public enum DrelOAuthDeviceKeyError: Error {
    case unavailable
}

public final class DrelOAuthSecureEnclaveKeyStore: DrelOAuthDeviceKeyStoring {
    private let service: String
    private let lock = NSLock()

    public init(service: String = "com.webbridgekit.superapp.oauth.device-key") {
        self.service = service
    }

    public func currentIdentity() throws -> DrelOAuthDeviceIdentity? {
        try queryIdentity()
    }

    public func generateIdentity() throws -> DrelOAuthDeviceIdentity {
        lock.lock()
        defer { lock.unlock() }
        try deleteIdentity()

        if let secureEnclave = try? SecureEnclave.P256.Signing.PrivateKey() {
            let identity = DrelOAuthDeviceIdentity(deviceID: UUID().uuidString, usesSecureEnclave: true)
            try save(identity: identity, data: secureEnclave.dataRepresentation, isSecureEnclave: true)
            return identity
        }

        let key = try P256.Signing.PrivateKey()
        let identity = DrelOAuthDeviceIdentity(deviceID: UUID().uuidString, usesSecureEnclave: false)
        try save(identity: identity, data: key.rawRepresentation, isSecureEnclave: false)
        return identity
    }

    public func sign(payload: Data) throws -> P256.Signing.ECDSASignature {
        let identity = try queryIdentity()
        guard let identity else { throw DrelOAuthDeviceKeyError.unavailable }
        if identity.usesSecureEnclave,
           let data = try keychainData(account: identity.deviceID),
           let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) {
            return try key.signature(for: payload)
        }
        guard !identity.usesSecureEnclave,
              let data = try keychainData(account: identity.deviceID),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: data) else {
            throw DrelOAuthDeviceKeyError.unavailable
        }
        return try key.signature(for: payload)
    }

    public func publicKeyJWK() throws -> [String: String] {
        let identity = try queryIdentity()
        guard let identity else { throw DrelOAuthDeviceKeyError.unavailable }
        let key: P256.Signing.PublicKey
        if identity.usesSecureEnclave,
           let data = try keychainData(account: identity.deviceID),
           let secureEnclaveKey = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) {
            key = secureEnclaveKey.publicKey
        } else {
            guard let data = try keychainData(account: identity.deviceID),
                  let nonEnclaveKey = try? P256.Signing.PrivateKey(rawRepresentation: data) else {
                throw DrelOAuthDeviceKeyError.unavailable
            }
            key = nonEnclaveKey.publicKey
        }
        let x = key.x963Representation.suffix(64).prefix(32)
        let y = key.x963Representation.suffix(32)
        return [
            "kty": "EC",
            "crv": "P-256",
            "x": DrelOAuthPKCE.base64URL(Data(x)),
            "y": DrelOAuthPKCE.base64URL(Data(y))
        ]
    }

    public func deleteIdentity() throws {
        lock.lock()
        defer { lock.unlock() }
        if let identity = try queryIdentityLocked() {
            let store = DrelOAuthKeychainStore(service: service)
            try store.delete(account: identity.deviceID)
        }
    }

    private func queryIdentity() throws -> DrelOAuthDeviceIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return try queryIdentityLocked()
    }

    private func queryIdentityLocked() throws -> DrelOAuthDeviceIdentity? {
        guard let data = try keychainData(account: "identity") else { return nil }
        return try JSONDecoder().decode(DrelOAuthDeviceIdentity.self, from: data)
    }

    private func save(identity: DrelOAuthDeviceIdentity, data: Data, isSecureEnclave: Bool) throws {
        let store = DrelOAuthKeychainStore(service: service)
        try store.save(.init(grantID: identity.deviceID, refreshToken: ""), account: identity.deviceID)
        var query = keychainQuery(account: "identity")
        query[kSecValueData as String] = try JSONEncoder().encode(identity)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: try JSONEncoder().encode(identity)] as CFDictionary)
        }
        guard status == errSecSuccess else { throw DrelOAuthKeychainError(status: status) }
    }

    private func keychainData(account: String) throws -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw DrelOAuthKeychainError(status: status)
        }
        return result as? Data
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
