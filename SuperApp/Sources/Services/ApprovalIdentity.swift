import CryptoKit
import Foundation
import Security

struct ApprovalIdentity {
    let privateKey: Curve25519.Signing.PrivateKey

    init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    var keyID: String {
        Self.keyID(for: privateKey.publicKey.rawRepresentation)
    }

    var subject: String {
        "drel:\(keyID)"
    }

    var login: String {
        "drel-\(keyID.prefix(12).lowercased())"
    }

    var publicKeyPEM: String {
        let der = Data([
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
            0x03, 0x21, 0x00
        ]) + privateKey.publicKey.rawRepresentation
        let body = der.base64EncodedString(options: [.lineLength64Characters])
        return "-----BEGIN PUBLIC KEY-----\n\(body)\n-----END PUBLIC KEY-----"
    }

    func assertion(requestID: String, ticket: String, actionID: String) -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["alg": "EdDSA", "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": "drel",
            "aud": "drel-approval",
            "sub": subject,
            "login": login,
            "requestId": requestID,
            "ticketHash": Self.ticketHash(ticket),
            "actionId": actionID,
            "jti": UUID().uuidString,
            "iat": now,
            "exp": now + 120
        ]
        let headerPart = Self.base64URL(try! JSONSerialization.data(
            withJSONObject: header,
            options: [.sortedKeys]
        ))
        let payloadPart = Self.base64URL(try! JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ))
        let signingInput = "\(headerPart).\(payloadPart)"
        let signature = try! privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(Self.base64URL(signature))"
    }

    static func ticketHash(_ ticket: String) -> String {
        let digest = SHA256.hash(data: Data(ticket.utf8))
        return base64URL(Data(digest))
    }

    private static func keyID(for publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey)
        return String(base64URL(Data(digest)).prefix(32))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class ApprovalIdentityKeyStore {
    static let shared = ApprovalIdentityKeyStore()

    private let service = "com.webbridgekit.drel.approval-identity"
    private let account = "actor-key-v1"
    private(set) var identity: ApprovalIdentity

    private init() {
        let key: Curve25519.Signing.PrivateKey
        if let stored = Self.readKey(service: service, account: account),
           let restored = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) {
            key = restored
        } else {
            key = Curve25519.Signing.PrivateKey()
            Self.saveKey(key.rawRepresentation, service: service, account: account)
        }
        identity = ApprovalIdentity(privateKey: key)
    }

    private static func readKey(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func saveKey(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }
}
