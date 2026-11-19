import CryptoKit
import Foundation

public enum DrelOAuthPKCEError: Error {
    case generationFailed
}

public struct DrelOAuthPKCEPair: Equatable {
    public let verifier: String
    public let challenge: String
    public let method: String
}

public enum DrelOAuthPKCE {
    public static func generate(randomness: @escaping (Int) throws -> Data = { count in
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw DrelOAuthPKCEError.generationFailed }
        return Data(bytes)
    }) throws -> DrelOAuthPKCEPair {
        let random = try randomness(32)
        let verifier = base64URL(random)
        return .init(verifier: verifier, challenge: base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))), method: "S256")
    }

    public static func randomToken(randomness: @escaping (Int) throws -> Data = { count in
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw DrelOAuthPKCEError.generationFailed }
        return Data(bytes)
    }) throws -> String {
        base64URL(try randomness(24))
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum DrelOAuthJSONWebToken {
    static func make(
        claims: [String: Any],
        keyStore: DrelOAuthDeviceKeyStoring,
        deviceID: String,
        accessToken: String? = nil
    ) async throws -> String {
        var header: [String: Any] = ["typ": "dpop+jwt", "alg": "ES256"]
        header["jwk"] = try keyStore.publicKeyJWK()
        var proofClaims = claims
        let now = Int(Date().timeIntervalSince1970)
        proofClaims["iat"] = now
        proofClaims["exp"] = now + 120
        proofClaims["jti"] = try DrelOAuthPKCE.randomToken()
        proofClaims["deviceId"] = deviceID
        if let accessToken {
            proofClaims["ath"] = DrelOAuthPKCE.base64URL(Data(SHA256.hash(data: Data(accessToken.utf8))))
        }
        let encoded = (try encodedJSON(header)) + "." + (try encodedJSON(proofClaims))
        let signature = try keyStore.sign(payload: Data(encoded.utf8))
        return encoded + "." + DrelOAuthPKCE.base64URL(signature.rawRepresentation)
    }

    private static func encodedJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return DrelOAuthPKCE.base64URL(data)
    }
}
