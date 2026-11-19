import Foundation

public enum DrelOAuthError: Error, Equatable {
    case manifestMissing
    case manifestInvalid(DrelOAuthManifestValidationError)
    case invalidRequest(String)
    case scopeExceeded
    case pairingRequired
    case consentRequired
    case networkUnavailable
    case invalidGrant
    case userCancelled
    case keyUnavailable
    case authorizationRequired
}

public struct DrelOAuthScope: Hashable, Codable, Sendable {
    public let name: String

    public init(_ name: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard name.count <= 128, !name.isEmpty,
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DrelOAuthError.invalidRequest("invalid scope")
        }
        self.name = name
    }

    public static func set(_ names: [String]) throws -> Set<DrelOAuthScope> {
        try Set(names.map(DrelOAuthScope.init))
    }
}

public struct DrelOAuthGrant: Codable, Equatable, Sendable {
    public let contextKey: String
    public let gatewayIdentity: String
    public let appID: String
    public let documentOrigin: String
    public let clientID: String
    public let resourceOrigin: String
    public let grantID: String
    public let scope: Set<DrelOAuthScope>
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAt: Date
    public let refreshTokenExpiresAt: Date
    public let lastRefreshedAt: Date

    public init(
        contextKey: String,
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String,
        clientID: String,
        resourceOrigin: String,
        grantID: String,
        scope: Set<DrelOAuthScope>,
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date,
        lastRefreshedAt: Date = Date()
    ) {
        self.contextKey = contextKey
        self.gatewayIdentity = gatewayIdentity
        self.appID = appID
        self.documentOrigin = documentOrigin
        self.clientID = clientID
        self.resourceOrigin = resourceOrigin
        self.grantID = grantID
        self.scope = scope
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.lastRefreshedAt = lastRefreshedAt
    }
}

public struct DrelOAuthGrantStatus: Equatable, Codable, Sendable {
    public var available: Bool
    public var status: String
    public var grantID: String?
    public var scope: String?
    public var accessTokenExpiresIn: Int?
}

public struct DrelOAuthFetchResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let bodyType: String
    public let body: DrelOAuthFetchBody
}

public enum DrelOAuthFetchBody: @unchecked Sendable {
    case json(Any)
    case text(String)
    case base64(String)

    public static func == (lhs: DrelOAuthFetchBody, rhs: DrelOAuthFetchBody) -> Bool {
        switch (lhs, rhs) {
        case let (.text(left), .text(right)): return left == right
        case let (.base64(left), .base64(right)): return left == right
        case let (.json(left), .json(right)):
            guard let leftData = try? JSONSerialization.data(withJSONObject: left),
                  let rightData = try? JSONSerialization.data(withJSONObject: right) else { return false }
            return leftData == rightData
        default: return false
        }
    }
}
