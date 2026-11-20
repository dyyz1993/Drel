import Foundation
import WebBridgeKit

public enum DrelOAuthManifestValidationError: Error, Equatable {
    case unsupportedSchemaVersion
    case invalidProvider
    case invalidClientID
    case invalidAuthorizationBaseURL
    case invalidResourceOrigin
    case invalidPathPrefix
    case invalidScope(String)
    case invalidRefreshPolicy
    case forbiddenScope(String)
    case resourceOriginNotInAllowedOrigins
}

public struct DrelOAuthRefreshPolicy: Codable, Equatable, Sendable {
    public let idleTimeoutSeconds: Int
    public let absoluteLifetimeSeconds: Int
    public let rotateOnRefresh: Bool
}

public struct DrelOAuthManifestAuthorization: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let provider: String
    public let clientId: String
    public let resource: DrelOAuthResourceDeclaration
    public let scopes: [String]
    public let refreshPolicy: DrelOAuthRefreshPolicy
}

public struct DrelOAuthResourceDeclaration: Codable, Equatable, Sendable {
    public let baseURL: String
    public let pathPrefix: String
}

public struct DrelOAuthValidatedManifest: Equatable, Sendable {
    public let appID: String
    public let startURL: String
    public let authorization: DrelOAuthManifestAuthorization
    public let resourceOrigin: String
    public let scopes: Set<DrelOAuthScope>

    public static let provider = "drel-device-grant-v1"
    static let neverGrantedByDefault = ["settings.write", "providers.write", "admin", "deploy"]
}

public enum DrelOAuthManifestValidator {
    public static func validate(
        rawManifestData: Data,
        allowedOrigins: [String],
        trustedAppID: String
    ) throws -> DrelOAuthValidatedManifest {
        struct SignedEnvelope: Codable {
            let appId: String
            let startURL: String
            let allowedOrigins: [String]
            let authorization: DrelOAuthManifestAuthorization?
        }

        let manifest = try JSONDecoder().decode(SignedEnvelope.self, from: rawManifestData)
        guard manifest.appId == trustedAppID else {
            throw DrelOAuthError.manifestInvalid(.invalidClientID)
        }
        guard let authorization = manifest.authorization else {
            throw DrelOAuthError.manifestMissing
        }
        return try validate(
            authorization: authorization,
            startURL: manifest.startURL,
            allowedOrigins: allowedOrigins,
            trustedAppID: trustedAppID
        )
    }

    public static func validate(
        authorization: DrelOAuthManifestAuthorization,
        startURL: String,
        allowedOrigins: [String],
        trustedAppID: String
    ) throws -> DrelOAuthValidatedManifest {
        guard authorization.schemaVersion == "1" else {
            throw DrelOAuthError.manifestInvalid(.unsupportedSchemaVersion)
        }
        guard authorization.provider == DrelOAuthValidatedManifest.provider else {
            throw DrelOAuthError.manifestInvalid(.invalidProvider)
        }
        guard isValidHostID(authorization.clientId), authorization.clientId == trustedAppID else {
            throw DrelOAuthError.manifestInvalid(.invalidClientID)
        }
        guard let resourceURL = URL(string: authorization.resource.baseURL),
              resourceURL.scheme?.lowercased() == "https",
              resourceURL.host != nil,
              resourceURL.path.isEmpty || resourceURL.path == "/",
              resourceURL.query == nil,
              resourceURL.fragment == nil else {
            throw DrelOAuthError.manifestInvalid(.invalidResourceOrigin)
        }
        guard authorization.resource.pathPrefix.hasPrefix("/"),
              !authorization.resource.pathPrefix.contains("//"),
              !authorization.resource.pathPrefix.contains(".."),
              authorization.resource.pathPrefix.hasSuffix("/") else {
            throw DrelOAuthError.manifestInvalid(.invalidPathPrefix)
        }

        let scopeNames = Set(authorization.scopes)
        guard scopeNames.count == authorization.scopes.count else {
            throw DrelOAuthError.manifestInvalid(.invalidScope("duplicate"))
        }
        let scopes = try Set(authorization.scopes.map(DrelOAuthScope.init))
        for forbidden in scopeNames where DrelOAuthValidatedManifest.neverGrantedByDefault.contains(forbidden) {
            throw DrelOAuthError.manifestInvalid(.forbiddenScope(forbidden))
        }

        guard authorization.refreshPolicy.idleTimeoutSeconds > 0,
              authorization.refreshPolicy.absoluteLifetimeSeconds >= authorization.refreshPolicy.idleTimeoutSeconds else {
            throw DrelOAuthError.manifestInvalid(.invalidRefreshPolicy)
        }

        let port = resourceURL.port.map { ":\($0)" } ?? ""
        let resourceOrigin = "\(resourceURL.scheme!.lowercased())://\(resourceURL.host!.lowercased())\(port)"
        let allowedCanonicalOrigins = allowedOrigins.compactMap(HTMLAppOrigin.canonicalDeclaredOrigin)
        guard !allowedOrigins.isEmpty,
              allowedCanonicalOrigins.count == allowedOrigins.count,
              allowedCanonicalOrigins.contains(resourceOrigin) else {
            throw DrelOAuthError.manifestInvalid(.resourceOriginNotInAllowedOrigins)
        }
        return DrelOAuthValidatedManifest(
            appID: trustedAppID,
            startURL: startURL,
            authorization: authorization,
            resourceOrigin: resourceOrigin,
            scopes: scopes
        )
    }

    public static func isAuthorizedPath(_ path: String, manifest: DrelOAuthValidatedManifest) -> Bool {
        guard path.hasPrefix(manifest.authorization.resource.pathPrefix),
              path.count > 1,
              !path.contains("//"),
              !path.contains(".."),
              !path.contains("?"),
              !path.contains("#") else { return false }
        return path.unicodeScalars.allSatisfy { $0 != "\0" }
    }


    static func isValidHostID(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !value.isEmpty && value.count <= 128 && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public enum DrelOAuthTrustedManifestReader {
    public static func validatedManifest(
        appID: String,
        trustRegistry: HTMLAppTrustRegistry,
        storage: HTMLAppRuntimeStorage = HTMLAppUserDefaultsStorage(),
        authorizationGatewayKey: String? = nil
    ) throws -> DrelOAuthValidatedManifest {
        guard let trustedManifest = trustRegistry.manifest(for: appID) else {
            throw DrelOAuthError.manifestMissing
        }
        let gatewayKey = authorizationGatewayKey ?? DrelOAuthGatewayAuthorizationStore.defaultGatewayKey()
        guard let authorization = try DrelOAuthAuthorizationSnapshotStore(
            storage: storage
        ).authorization(
            gatewayKey: gatewayKey,
            appID: appID,
            trustedManifest: trustedManifest
        ) else {
            throw DrelOAuthError.manifestMissing
        }
        return try DrelOAuthManifestValidator.validate(
            authorization: authorization,
            startURL: trustedManifest.startURL,
            allowedOrigins: trustedManifest.allowedOrigins,
            trustedAppID: appID
        )
    }
}

enum DrelOAuthGatewayAuthorizationStore {
    static func defaultGatewayKey() -> String {
        guard let gateway = HTMLAppGatewayRegistry(
            officialGateway: DrelGatewayConfiguration.official
        ).activeGateway() else { return "" }
        return DrelOAuthGatewayAuthorizationIntegration.authorizationGatewayKey(gateway)
    }
}
