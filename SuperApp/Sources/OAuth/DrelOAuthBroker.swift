import CryptoKit
import Foundation
import UIKit
import WebBridgeKit

public struct DrelOAuthAuthorizationRequest: Equatable, Sendable {
    public let gatewayIdentity: String
    public let appID: String
    public let documentOrigin: String
    public let clientID: String
    public let resourceOrigin: String
    public let scope: Set<DrelOAuthScope>

    var contextKey: String {
        [gatewayIdentity, appID, documentOrigin, clientID, resourceOrigin].joined(separator: "|")
    }
}

public protocol DrelOAuthConsentPresenting {
    @MainActor
    func request(
        appName: String,
        resourceOrigin: String,
        scopes: [String],
        completion: @escaping (Bool) -> Void
    )
}

public final class DrelOAuthAlertConsentPresenter: DrelOAuthConsentPresenting {
    public init() {}

    @MainActor
    public func request(
        appName: String,
        resourceOrigin: String,
        scopes: [String],
        completion: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "允许 \(appName) 访问 VOT？",
            message: "\(resourceOrigin)\n\n\(scopes.joined(separator: "\n"))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "允许", style: .default) { _ in completion(true) })
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let root = scene?.keyWindow?.rootViewController?.topMost() ?? scene?.keyWindow?.rootViewController
        root?.present(alert, animated: true)
    }
}

private extension UIViewController {
    func topMost() -> UIViewController {
        var current = self
        while let presented = current.presentedViewController { current = presented }
        return current
    }
}

public final class DrelOAuthBroker {
    private let trustRegistry: HTMLAppTrustRegistry
    private let storage: HTMLAppRuntimeStorage
    private let authorizationGatewayKey: String?
    private let keyStore: DrelOAuthDeviceKeyStoring
    private let tokenStore: DrelOAuthTokenStoring
    private let service: DrelOAuthService
    private let consentPresenter: DrelOAuthConsentPresenting
    private let now: () -> Date
    private let refreshFlight = DrelOAuthRefreshFlight()
    private let metadataStore = DrelOAuthKeychainGrantMetadataStore()

    public init(
        trustRegistry: HTMLAppTrustRegistry = HTMLAppRuntimeCenter.shared.trustRegistry,
        storage: HTMLAppRuntimeStorage = HTMLAppUserDefaultsStorage(),
        authorizationGatewayKey: String? = nil,
        keyStore: DrelOAuthDeviceKeyStoring = DrelOAuthSecureEnclaveKeyStore(),
        tokenStore: DrelOAuthTokenStoring = DrelOAuthKeychainTokenStore(),
        httpClient: DrelOAuthHTTPClient = DrelOAuthURLSessionClient(),
        consentPresenter: DrelOAuthConsentPresenting = DrelOAuthAlertConsentPresenter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.trustRegistry = trustRegistry
        self.storage = storage
        self.authorizationGatewayKey = authorizationGatewayKey
        self.keyStore = keyStore
        self.tokenStore = tokenStore
        self.service = DrelOAuthService(keyStore: keyStore, httpClient: httpClient)
        self.consentPresenter = consentPresenter
        self.now = now
    }

    public func authorizationRequest(
        scopes: [String],
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String,
        pairingRequestID: String?
    ) async throws -> DrelOAuthGrantStatus {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        let requested = try DrelOAuthScope.set(scopes)
        guard requested.isSubset(of: manifest.scopes) else { throw DrelOAuthError.scopeExceeded }
        let request = try self.request(manifest: manifest, gatewayIdentity: gatewayIdentity, documentOrigin: documentOrigin, scope: requested)
        if let grant = try? loadGrant(for: request),
           grant.refreshTokenExpiresAt > now(),
           requested.isSubset(of: grant.scope) {
            return status(for: grant)
        }
        guard let pairingRequestID, !pairingRequestID.isEmpty else {
            throw DrelOAuthError.pairingRequired
        }
        return try await performAuthorization(request: request, pairingRequestID: pairingRequestID)
    }

    public func status(
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String
    ) throws -> DrelOAuthGrantStatus {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        let request = try self.request(manifest: manifest, gatewayIdentity: gatewayIdentity, documentOrigin: documentOrigin, scope: [])
        guard let grant = try? loadGrant(for: request), grant.refreshTokenExpiresAt > now() else {
            return .init(available: true, status: "consent_required", grantID: nil, scope: nil, accessTokenExpiresIn: nil)
        }
        return status(for: grant)
    }

    public func fetch(
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String,
        request: [String: Any]
    ) async throws -> DrelOAuthFetchResponse {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        _ = try self.request(manifest: manifest, gatewayIdentity: gatewayIdentity, documentOrigin: documentOrigin, scope: [])
        guard let path = request["path"] as? String,
              DrelOAuthManifestValidator.isAuthorizedPath(path, manifest: manifest) else {
            throw DrelOAuthError.invalidRequest("path outside declaration")
        }
        guard let method = (request["method"] as? String ?? "GET").uppercased() as String?,
              ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) else {
            throw DrelOAuthError.invalidRequest("method")
        }
        let headers = request["headers"] as? [String: String] ?? [:]
        let forbidden = ["authorization", "cookie", "dpop", "host"]
        guard !headers.keys.contains(where: { forbidden.contains($0.lowercased()) || $0.lowercased().hasPrefix("drel-") }) else {
            throw DrelOAuthError.invalidRequest("forbidden header")
        }
        let grant = try await validGrant(
            gatewayIdentity: gatewayIdentity,
            appID: appID,
            documentOrigin: documentOrigin
        )
        guard let url = URL(string: manifest.resourceOrigin + path) else {
            throw DrelOAuthError.invalidRequest("path")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        if let body = request["body"] {
            urlRequest.httpBody = try encodeBody(body, type: request["bodyType"] as? String)
        }
        let (data, response) = try await service.authorizedFetch(request: urlRequest, accessToken: grant.accessToken)
        if response.statusCode == 401 {
            let refreshedGrant = try await refresh(grant: grant)
            let retry = try await service.authorizedFetch(request: urlRequest, accessToken: refreshedGrant.accessToken)
            return try makeResponse(for: retry.0, response: retry.1)
        } else if response.statusCode == 403 {
            throw DrelOAuthError.scopeExceeded
        }
        return try makeResponse(for: data, response: response)
    }

    public func revoke(
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String
    ) async throws {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        let request = try self.request(manifest: manifest, gatewayIdentity: gatewayIdentity, documentOrigin: documentOrigin, scope: [])
        if let grant = try? loadGrant(for: request) {
            try? await service.revoke(resourceBaseURL: manifest.resourceOrigin, grantID: grant.grantID, refreshToken: grant.refreshToken)
        }
        try tokenStore.delete(account: request.contextKey)
        try? metadataStore.delete(contextKey: request.contextKey)
    }

    public func revokeAll(appIDs: [String]) async throws {
        for appID in appIDs {
            guard let manifest = try? DrelOAuthTrustedManifestReader.validatedManifest(
                appID: appID,
                trustRegistry: trustRegistry,
                storage: storage,
                authorizationGatewayKey: authorizationGatewayKey
            ) else { continue }
            guard let origin = HTMLAppOrigin.canonicalOrigin(forDocumentURL: URL(string: manifest.startURL) ?? URL(fileURLWithPath: "/")) else { continue }
            try? await revoke(
                gatewayIdentity: HTMLAppRuntimeCenter.shared.gatewayIdentity,
                appID: appID,
                documentOrigin: origin
            )
        }
        try tokenStore.removeAll()
        await MainActor.run {
            DrelOAuthBridgeInstaller.resetBridgeState()
        }
    }

    public func validGrant(
        gatewayIdentity: String,
        appID: String,
        documentOrigin: String
    ) async throws -> DrelOAuthGrant {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        let request = try self.request(manifest: manifest, gatewayIdentity: gatewayIdentity, documentOrigin: documentOrigin, scope: [])
        guard let grant = try? loadGrant(for: request), grant.refreshTokenExpiresAt > now() else {
            throw DrelOAuthError.authorizationRequired
        }
        return try await refreshIfNeeded(grant)
    }

    @discardableResult
    public func refreshIfNeeded(_ grant: DrelOAuthGrant) async throws -> DrelOAuthGrant {
        guard grant.accessTokenExpiresAt - 30 <= now() else { return grant }
        return try await refresh(grant: grant)
    }

    @discardableResult
    public func refresh(grant: DrelOAuthGrant) async throws -> DrelOAuthGrant {
        try await refreshFlight.run(contextKey: grant.contextKey) { [service, tokenStore, keyStore, grant, now] in
            let response = try await service.refresh(
                resourceBaseURL: grant.resourceOrigin,
                grantID: grant.grantID,
                refreshToken: grant.refreshToken
            )
            let nowDate = now()
            let refreshed = DrelOAuthGrant(
                contextKey: grant.contextKey,
                gatewayIdentity: grant.gatewayIdentity,
                appID: grant.appID,
                documentOrigin: grant.documentOrigin,
                clientID: grant.clientID,
                resourceOrigin: grant.resourceOrigin,
                grantID: response.grantId,
                scope: try DrelOAuthScope.set(response.scope.components(separatedBy: " ").filter { !$0.isEmpty }),
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accessTokenExpiresAt: nowDate.addingTimeInterval(TimeInterval(response.expiresIn)),
                refreshTokenExpiresAt: nowDate.addingTimeInterval(TimeInterval(response.refreshExpiresIn)),
                lastRefreshedAt: nowDate
            )
            try tokenStore.saveRefreshToken(refreshed.refreshToken, account: refreshed.contextKey)
            _ = try keyStore.currentIdentity() ?? { try keyStore.generateIdentity() }()
            return refreshed
        }
    }

    private func performAuthorization(
        request: DrelOAuthAuthorizationRequest,
        pairingRequestID: String
    ) async throws -> DrelOAuthGrantStatus {
        let manifest = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: request.appID,
            trustRegistry: trustRegistry,
            storage: storage,
            authorizationGatewayKey: authorizationGatewayKey
        )
        let allowed = await withCheckedContinuation { continuation in
            Task { @MainActor in
                consentPresenter.request(appName: request.appID, resourceOrigin: request.resourceOrigin, scopes: request.scope.map(\.name).sorted()) {
                    continuation.resume(returning: $0)
                }
            }
        }
        guard allowed else { throw DrelOAuthError.userCancelled }
        let grantResponse = try await service.completeGrant(
            resourceBaseURL: manifest.resourceOrigin,
            pairingRequestID: pairingRequestID,
            request: request
        )
        let grantedScope = try DrelOAuthScope.set(grantResponse.scope.components(separatedBy: " ").filter { !$0.isEmpty })
        guard grantedScope.isSubset(of: manifest.scopes), request.scope.isSubset(of: grantedScope) else {
            throw DrelOAuthError.scopeExceeded
        }
        let currentTime = now()
        let grant = DrelOAuthGrant(
            contextKey: request.contextKey,
            gatewayIdentity: request.gatewayIdentity,
            appID: request.appID,
            documentOrigin: request.documentOrigin,
            clientID: request.clientID,
            resourceOrigin: request.resourceOrigin,
            grantID: grantResponse.grantId,
            scope: grantedScope,
            accessToken: grantResponse.accessToken,
            refreshToken: grantResponse.refreshToken,
            accessTokenExpiresAt: currentTime.addingTimeInterval(TimeInterval(grantResponse.expiresIn)),
            refreshTokenExpiresAt: currentTime.addingTimeInterval(TimeInterval(grantResponse.refreshExpiresIn)),
            lastRefreshedAt: currentTime
        )
        try tokenStore.saveRefreshToken(grant.refreshToken, account: grant.contextKey)
        try metadataStore.save(grant)
        return status(for: grant)
    }

    private func loadGrant(for request: DrelOAuthAuthorizationRequest) throws -> DrelOAuthGrant {
        guard let metadata = try metadataStore.load(contextKey: request.contextKey),
              let token = try tokenStore.loadRefreshToken(account: request.contextKey),
              metadata.refreshToken == token,
              metadata.gatewayIdentity == request.gatewayIdentity,
              metadata.appID == request.appID,
              metadata.documentOrigin == request.documentOrigin,
              metadata.clientID == request.clientID,
              metadata.resourceOrigin == request.resourceOrigin else {
            throw DrelOAuthError.authorizationRequired
        }
        return metadata
    }

    private func request(
        manifest: DrelOAuthValidatedManifest,
        gatewayIdentity: String,
        documentOrigin: String,
        scope: Set<DrelOAuthScope>
    ) throws -> DrelOAuthAuthorizationRequest {
        guard let startOrigin = HTMLAppOrigin.canonicalOrigin(forDocumentURL: URL(string: manifest.startURL) ?? URL(fileURLWithPath: "/")),
              startOrigin == documentOrigin else {
            throw DrelOAuthError.invalidRequest("untrusted origin")
        }
        return DrelOAuthAuthorizationRequest(
            gatewayIdentity: gatewayIdentity,
            appID: manifest.appID,
            documentOrigin: startOrigin,
            clientID: manifest.authorization.clientId,
            resourceOrigin: manifest.resourceOrigin,
            scope: scope
        )
    }

    private func status(for grant: DrelOAuthGrant) -> DrelOAuthGrantStatus {
        .init(
            available: true,
            status: "granted",
            grantID: grant.grantID,
            scope: grant.scope.map(\.name).sorted().joined(separator: " "),
            accessTokenExpiresIn: max(0, Int(grant.accessTokenExpiresAt.timeIntervalSince(now())))
        )
    }

    private func encodeBody(_ body: Any, type: String?) throws -> Data {
        switch type {
        case "text":
            guard let value = body as? String else { throw DrelOAuthError.invalidRequest("body") }
            return Data(value.utf8)
        case "base64":
            guard let value = body as? String, let data = Data(base64Encoded: value) else {
                throw DrelOAuthError.invalidRequest("body")
            }
            return data
        case "json", nil:
            guard JSONSerialization.isValidJSONObject(body) else { throw DrelOAuthError.invalidRequest("body") }
            return try JSONSerialization.data(withJSONObject: body)
        default:
            throw DrelOAuthError.invalidRequest("bodyType")
        }
    }

    private func makeResponse(for data: Data, response: HTTPURLResponse) throws -> DrelOAuthFetchResponse {
        let allowedHeaders = ["content-type", "etag", "last-modified", "cache-control"]
        var headers: [String: String] = [:]
        for (rawKey, rawValue) in response.allHeaderFields {
            let key = String(describing: rawKey).lowercased()
            guard allowedHeaders.contains(key) else { continue }
            headers[key] = String(describing: rawValue)
        }
        let contentType = headers["content-type"] ?? ""
        if contentType.contains("json"), let json = try? JSONSerialization.jsonObject(with: data) {
            return .init(status: response.statusCode, headers: headers, bodyType: "json", body: .json(json))
        }
        return .init(status: response.statusCode, headers: headers, bodyType: "text", body: .text(String(bytes: data, encoding: .utf8) ?? ""))
    }
}

public actor DrelOAuthRefreshFlight {
    private var tasks: [String: Task<DrelOAuthGrant, Error>] = [:]

    public init() {}

    public func run(
        contextKey: String,
        operation: @escaping @Sendable () async throws -> DrelOAuthGrant
    ) async throws -> DrelOAuthGrant {
        if let existing = tasks[contextKey] {
            return try await existing.value
        }
        let task = Task { try await operation() }
        tasks[contextKey] = task
        defer { tasks[contextKey] = nil }
        return try await task.value
    }

}

extension DrelOAuthBroker {
    func storeGrantForTesting(_ grant: DrelOAuthGrant) throws {
        try tokenStore.saveRefreshToken(grant.refreshToken, account: grant.contextKey)
        try metadataStore.save(grant)
    }
}
