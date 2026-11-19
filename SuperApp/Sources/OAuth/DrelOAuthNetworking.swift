import CryptoKit
import Foundation

public struct DrelOAuthGrantResponse: Codable, Equatable, Sendable {
    public let grantId: String
    public let workspaceId: String?
    public let scope: String
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let refreshToken: String
    public let refreshExpiresIn: Int
    public let returnRoute: String?
}

public protocol DrelOAuthHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct DrelOAuthURLSessionClient: DrelOAuthHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DrelOAuthError.networkUnavailable }
        return (data, http)
    }
}

public final class DrelOAuthService {
    private let keyStore: DrelOAuthDeviceKeyStoring
    private let httpClient: DrelOAuthHTTPClient

    public init(keyStore: DrelOAuthDeviceKeyStoring, httpClient: DrelOAuthHTTPClient) {
        self.keyStore = keyStore
        self.httpClient = httpClient
    }

    public func completeGrant(
        resourceBaseURL: String,
        pairingRequestID: String,
        request: DrelOAuthAuthorizationRequest
    ) async throws -> DrelOAuthGrantResponse {
        let grantURL = URL(string: resourceBaseURL + "/api/v1/auth/drel/grants")!
        let deviceGrant = try await DrelOAuthJSONWebToken.make(
            claims: [
                "aud": request.clientID,
                "clientId": request.clientID,
                "appId": request.appID,
                "pairingRequestId": pairingRequestID,
                "resourceOrigin": request.resourceOrigin,
                "scope": request.scope.map(\.name).sorted(),
                "htm": "POST",
                "htu": grantURL.absoluteString,
            ],
            keyStore: keyStore,
            deviceID: "drel-device",
            typ: "drel-device-grant+jwt"
        )
        let body: [String: Any] = [
            "pairingRequestId": pairingRequestID,
            "clientId": request.clientID,
            "requestedScopes": request.scope.map(\.name).sorted(),
            "deviceGrant": deviceGrant
        ]
        var urlRequest = URLRequest(url: grantURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let proof = try await proof(for: urlRequest, accessToken: nil)
        urlRequest.setValue(proof, forHTTPHeaderField: "DPoP")
        return try await execute(urlRequest)
    }

    public func refresh(resourceBaseURL: String, grantID: String, refreshToken: String) async throws -> DrelOAuthGrantResponse {
        let body: [String: Any] = ["grantId": grantID, "refreshToken": refreshToken]
        let url = URL(string: resourceBaseURL + "/api/v1/auth/drel/refresh")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let proof = try await proof(for: urlRequest, accessToken: nil)
        urlRequest.setValue(proof, forHTTPHeaderField: "DPoP")
        return try await execute(urlRequest)
    }

    public func revoke(resourceBaseURL: String, grantID: String, refreshToken: String) async throws {
        let body: [String: Any] = ["grantId": grantID, "refreshToken": refreshToken]
        let url = URL(string: resourceBaseURL + "/api/v1/auth/drel/revoke")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let proof = try await proof(for: urlRequest, accessToken: nil)
        urlRequest.setValue(proof, forHTTPHeaderField: "DPoP")
        _ = try await executeBody(urlRequest, expected: [200, 204])
    }

    public func authorizedFetch(
        request: URLRequest,
        accessToken: String
    ) async throws -> (Data, HTTPURLResponse) {
        let proof = try await proof(for: request, accessToken: accessToken)
        var authorized = request
        authorized.setValue("DPoP \(accessToken)", forHTTPHeaderField: "Authorization")
        authorized.setValue(proof, forHTTPHeaderField: "DPoP")
        return try await httpClient.data(for: authorized)
    }

    private func proof(for request: URLRequest, accessToken: String?) async throws -> String {
        let identity = try keyStore.currentIdentity() ?? { try keyStore.generateIdentity() }()
        let targetURL = request.url?.absoluteString ?? ""
        var claims: [String: Any] = ["htm": request.httpMethod ?? "GET", "htu": targetURL]
        if let body = request.httpBody, !body.isEmpty {
            claims["requestBodyHash"] = DrelOAuthPKCE.base64URL(Data(SHA256.hash(data: body)))
        }
        return try await DrelOAuthJSONWebToken.make(
            claims: claims,
            keyStore: keyStore,
            deviceID: identity.deviceID,
            accessToken: accessToken
        )
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await executeBody(request, expected: [200])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func executeBody(_ request: URLRequest, expected: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard expected.contains(response.statusCode) else { throw error(for: response.statusCode, data: data) }
            return (data, response)
        } catch let error as DrelOAuthError {
            throw error
        } catch {
            throw DrelOAuthError.networkUnavailable
        }
    }

    private func error(for status: Int, data: Data) -> Error {
        switch status {
        case 400, 401, 403, 404: return DrelOAuthError.invalidGrant
        case 429: return DrelOAuthError.networkUnavailable
        default: return DrelOAuthError.networkUnavailable
        }
    }
}
