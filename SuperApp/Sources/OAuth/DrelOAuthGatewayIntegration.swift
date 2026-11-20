import CryptoKit
import Foundation
import WebBridgeKit

public struct DrelOAuthManagedContext: Equatable, Sendable {
    public let gatewayIdentity: String
    public let authorizationGatewayKey: String
    public let appID: String
    public let origin: String
    public let parameters: [String: String]
}

@MainActor
final class DrelOAuthManagedContextStore {
    static let shared = DrelOAuthManagedContextStore()
    private(set) var current: DrelOAuthManagedContext?

    private init() {}

    func set(_ context: DrelOAuthManagedContext?) {
        current = context
    }
}

public struct DrelOAuthAuthorizationSnapshot: Codable, Equatable, Sendable {
    public let appID: String
    public let authorization: Data
    public let manifestFingerprint: String
}

struct DrelOAuthAuthorizationSnapshotState: Codable, Equatable {
    var gateways: [String: [String: DrelOAuthAuthorizationSnapshot]] = [:]
}

public final class DrelOAuthAuthorizationSnapshotStore {
    public static let shared = DrelOAuthAuthorizationSnapshotStore()
    private let storage: HTMLAppRuntimeStorage
    private let storageKey: String
    private let lock = NSLock()

    public init(
        storage: HTMLAppRuntimeStorage = HTMLAppUserDefaultsStorage(),
        storageKey: String = "com.webbridgekit.superapp.oauth.manifest-authorizations"
    ) {
        self.storage = storage
        self.storageKey = storageKey
    }

    func authorization(
        gatewayKey: String,
        appID: String,
        trustedManifest: HTMLAppManifest
    ) throws -> DrelOAuthManifestAuthorization? {
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot = loadLocked().gateways[gatewayKey]?[appID],
              snapshot.manifestFingerprint == DrelOAuthGatewayAuthorizationIntegration.fingerprint(trustedManifest)
        else { return nil }
        return try JSONDecoder().decode(DrelOAuthManifestAuthorization.self, from: snapshot.authorization)
    }

    func replaceGateway(
        gatewayKey: String,
        snapshots: [DrelOAuthAuthorizationSnapshot],
        removedAppIDs: [String] = [],
        storage: HTMLAppRuntimeStorage? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        var state = loadLocked()
        var gatewayState = state.gateways[gatewayKey] ?? [:]
        for appID in removedAppIDs { gatewayState.removeValue(forKey: appID) }
        for snapshot in snapshots { gatewayState[snapshot.appID] = snapshot }
        state.gateways[gatewayKey] = gatewayState
        persistLocked(state, storage: storage)
    }

    func removeAll(storage: HTMLAppRuntimeStorage? = nil) {
        lock.lock()
        defer { lock.unlock() }
        persistLocked(DrelOAuthAuthorizationSnapshotState(), storage: storage)
    }

    private func loadLocked() -> DrelOAuthAuthorizationSnapshotState {
        guard let data = storage.data(forKey: storageKey) else { return .init() }
        return (try? JSONDecoder().decode(DrelOAuthAuthorizationSnapshotState.self, from: data)) ?? .init()
    }

    private func persistLocked(_ state: DrelOAuthAuthorizationSnapshotState, storage storageOverride: HTMLAppRuntimeStorage?) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        (storageOverride ?? storage).set(data, forKey: storageKey)
    }
}

public final class DrelOAuthGatewayAuthorizationIntegration {
    private final class Transport: HTMLAppGatewayTransport {
        private let queue = NSLock()
        private var candidates: [String: Data] = [:]
        private let inner: HTMLAppGatewayTransport

        init(inner: HTMLAppGatewayTransport = HTMLAppGatewayURLSessionTransport()) {
            self.inner = inner
        }

        func beginTransaction() {
            queue.lock()
            candidates.removeAll()
            queue.unlock()
        }

        func candidate(appID: String) -> Data? {
            queue.lock()
            defer { queue.unlock() }
            return candidates[appID]
        }

        func get(_ url: URL, completion: @escaping (Result<HTMLAppGatewayTransportResponse, Error>) -> Void) {
            inner.get(url) { [weak self] result in
                guard let self else { return }
                if case .success(let response) = result, (200 ..< 300).contains(response.statusCode) {
                    self.recordCandidates(in: response.data)
                }
                completion(result)
            }
        }

        private func recordCandidates(in data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return }
            let rawManifests: [[String: Any]]
            if let envelope = object as? [String: Any], let manifests = envelope["manifests"] as? [[String: Any]] {
                rawManifests = manifests
            } else if let manifests = object as? [[String: Any]] {
                rawManifests = manifests
            } else if let manifest = object as? [String: Any] {
                rawManifests = [manifest]
            } else {
                return
            }
            queue.lock()
            for manifest in rawManifests {
                let appID = (manifest["appId"] as? String) ?? (manifest["app_id"] as? String) ?? ""
                guard !appID.isEmpty,
                      let authorization = manifest["authorization"],
                      JSONSerialization.isValidJSONObject(authorization),
                      let authorizationData = try? JSONSerialization.data(withJSONObject: authorization) else { continue }
                candidates[appID] = authorizationData
            }
            queue.unlock()
        }
    }

    private let transport = Transport()
    private let authorizationStore: DrelOAuthAuthorizationSnapshotStore
    public let onboardingService: HTMLAppGatewayOnboardingService

    public convenience init(
        gatewayRegistry: HTMLAppGatewayRegistry,
        trustRegistry: HTMLAppTrustRegistry = HTMLAppTrustRegistry(),
        permissionLedger: HTMLAppPermissionLedger = .shared,
        presentationMetadataStore: HTMLAppPresentationMetadataStore = HTMLAppPresentationMetadataStore(),
        allowsDevelopmentMode: Bool = false,
        authorizationStore: DrelOAuthAuthorizationSnapshotStore = .shared
    ) {
        let service = HTMLAppGatewayOnboardingService(
            gatewayRegistry: gatewayRegistry,
            trustRegistry: trustRegistry,
            permissionLedger: permissionLedger,
            webManifestAdapter: HTMLAppWebManifestAdapter(),
            presentationMetadataStore: presentationMetadataStore,
            allowsDevelopmentMode: allowsDevelopmentMode
        )
        self.init(
            onboardingService: service,
            authorizationStore: authorizationStore
        )
    }

    init(
        onboardingService: HTMLAppGatewayOnboardingService,
        authorizationStore: DrelOAuthAuthorizationSnapshotStore
    ) {
        self.onboardingService = onboardingService
        self.authorizationStore = authorizationStore
    }

    public func validate(
        _ gateway: HTMLAppGatewayConfiguration,
        completion: @escaping (Result<HTMLAppGatewayValidationReport, Error>) -> Void
    ) {
        transport.beginTransaction()
        onboardingService.validate(gateway, completion: completion)
    }

    public func activate(_ report: HTMLAppGatewayValidationReport) throws {
        try onboardingService.activate(report)
        let gatewayKey = Self.authorizationGatewayKey(report.gateway)
        var removedAppIDs: [String] = []
        let snapshots = report.manifests.compactMap { manifest -> DrelOAuthAuthorizationSnapshot? in
            guard let authorizationData = transport.candidate(appID: manifest.appID) else {
                removedAppIDs.append(manifest.appID)
                return nil
            }
            return DrelOAuthAuthorizationSnapshot(
                appID: manifest.appID,
                authorization: authorizationData,
                manifestFingerprint: Self.fingerprint(manifest)
            )
        }
        authorizationStore.replaceGateway(gatewayKey: gatewayKey, snapshots: snapshots, removedAppIDs: removedAppIDs)
    }

    public func removeGateway(id: String) throws {
        try onboardingService.removeGateway(id: id)
    }

    public static func authorizationGatewayKey(_ gateway: HTMLAppGatewayConfiguration) -> String {
        let publicKey = gateway.publicKey ?? "unsigned"
        let digest = SHA256.hash(data: Data("\(gateway.baseURL)|\(publicKey)".utf8))
        return "\(gateway.id)#\(gateway.publicKeyID ?? "unsigned")#\(DrelOAuthPKCE.base64URL(Data(digest)))"
    }

    static func fingerprint(_ manifest: HTMLAppManifest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(manifest)) ?? Data()
        return DrelOAuthPKCE.base64URL(Data(SHA256.hash(data: data)))
    }
}

public enum DrelOAuthAvailability {
    public static var hasAuthorizableApp: Bool {
        HTMLAppRuntimeCenter.shared.trustRegistry.registeredManifests().contains { manifest in
            (try? DrelOAuthTrustedManifestReader.validatedManifest(appID: manifest.appID, trustRegistry: HTMLAppRuntimeCenter.shared.trustRegistry)) != nil
        }
    }
}

@MainActor
public enum DrelOAuthLaunchIntegration {
    public static func context(
        for target: HTMLAppLaunchTarget,
        gatewayIdentity: String
    ) throws -> DrelOAuthManagedContext {
        let authorizationGatewayKey = DrelOAuthGatewayAuthorizationIntegration.authorizationGatewayKey(
            HTMLAppGatewayRegistry(officialGateway: DrelGatewayConfiguration.official).activeGateway()
                ?? DrelGatewayConfiguration.official
        )
        _ = try DrelOAuthTrustedManifestReader.validatedManifest(
            appID: target.manifest.appID,
            trustRegistry: HTMLAppRuntimeCenter.shared.trustRegistry,
            authorizationGatewayKey: authorizationGatewayKey
        )
        guard let origin = HTMLAppOrigin.canonicalOrigin(forDocumentURL: URL(string: target.manifest.startURL) ?? URL(fileURLWithPath: "/")) else {
            throw DrelOAuthError.manifestMissing
        }
        return DrelOAuthManagedContext(
            gatewayIdentity: gatewayIdentity,
            authorizationGatewayKey: authorizationGatewayKey,
            appID: target.manifest.appID,
            origin: origin,
            parameters: target.context.parameters
        )
    }

    public static func prepareLaunch(
        _ target: HTMLAppLaunchTarget,
        gatewayIdentity: String
    ) -> DrelOAuthManagedContext? {
        guard let context = try? context(for: target, gatewayIdentity: gatewayIdentity) else {
            DrelOAuthBridgeInstaller.prepareLaunch(context: DrelOAuthManagedContext(
                gatewayIdentity: "", authorizationGatewayKey: "", appID: "", origin: "", parameters: [:]
            ))
            return nil
        }
        DrelOAuthBridgeInstaller.prepareLaunch(context: context)
        return context
    }
}
