//
//  DrelPushAppCatalogCoordinator.swift
//  SuperApp
//
//  Push is the activation path for a user-visible HTML app. The signed
//  gateway catalog may be refreshed to verify the target, but it must not be
//  rendered as a list of unsolicited applications.
//

import Foundation
import WebBridgeKit

final class DrelPushAppCatalogCoordinator {
    static let shared = DrelPushAppCatalogCoordinator()

    private let runtime = HTMLAppRuntimeCenter.shared
    private let gatewayRegistry = HTMLAppGatewayRegistry(officialGateway: DrelGatewayConfiguration.official)
    private let receivedAppStore = HTMLAppPushActivationStore()
    private let lock = NSLock()
    private var isRefreshing = false
    private var pending: [(appID: String, route: String, completion: (Bool) -> Void)] = []

    private lazy var onboardingService = HTMLAppGatewayOnboardingService(
        gatewayRegistry: gatewayRegistry,
        trustRegistry: runtime.trustRegistry,
        permissionLedger: runtime.permissionLedger
    )

    private init() {}

    /// Makes an app visible only after its signed manifest permits the route
    /// carried in a received push. Completion always returns on the main queue.
    func activateIfTrusted(appID: String, route: String, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !appID.isEmpty, !route.isEmpty else {
            finish(completion, accepted: false)
            return
        }
        if routeIsTrusted(appID: appID, route: route) {
            receivedAppStore.activate(appID)
            finish(completion, accepted: true)
            return
        }

        lock.lock()
        pending.append((appID, route, completion))
        let shouldRefresh = !isRefreshing
        isRefreshing = true
        lock.unlock()
        guard shouldRefresh else { return }

        // Drel-owned app identifiers are signed by the configuration-free
        // official catalog. Push transport is deliberately independent: a
        // self-hosted/direct channel may deliver this notification, but it
        // must not replace the public trust source for a Drel app.
        let gateway = gateway(for: appID)
        onboardingService.validate(gateway) { [weak self] result in
            guard let self else { return }
            if case .success(let report) = result {
                try? self.onboardingService.activate(report)
            }
            self.finishPending()
        }
    }

    func activateIfTrusted(userInfo: [AnyHashable: Any]) {
        guard let appID = (userInfo["appId"] as? String) ?? (userInfo["appid"] as? String),
              let route = userInfo["route"] as? String else { return }
        activateIfTrusted(appID: appID, route: route)
    }

    func activateIfTrusted(userInfo: [String: Any]) {
        activateIfTrusted(userInfo: Dictionary(uniqueKeysWithValues: userInfo.map { (AnyHashable($0.key), $0.value) }))
    }

    private func finishPending() {
        lock.lock()
        let work = pending
        pending.removeAll()
        isRefreshing = false
        lock.unlock()

        for item in work {
            let accepted = routeIsTrusted(appID: item.appID, route: item.route)
            if accepted {
                receivedAppStore.activate(item.appID)
            }
            finish(item.completion, accepted: accepted)
        }
    }

    private func routeIsTrusted(appID: String, route: String) -> Bool {
        guard let manifest = runtime.trustRegistry.manifest(for: appID),
              manifest.allows(route: route) else { return false }
        return true
    }

    private func gateway(for appID: String) -> HTMLAppGatewayConfiguration {
        let base: HTMLAppGatewayConfiguration
        if appID.hasPrefix("dev.drel.") {
            base = DrelGatewayConfiguration.official
        } else {
            base = gatewayRegistry.activeGateway() ?? DrelGatewayConfiguration.official
        }
        return Self.deviceKeyScopedGateway(base)
    }

    /// 官方网关的清单拉取按本机推送标识加 `?key=` 作用域，使该 Key 注册的
    /// 私有清单进入本机视角（服务端 2026.10.29-keybind 起支持；私有清单对
    /// 匿名拉取不可见）。自建网关目录没有按 Key 隔离，不注入。先剥掉旧
    /// query 再注入当前标识，Key 重新生成后不会沿用残留的旧值。
    private static var supportsAudioLevel: Bool {
        #if DREL_152_MICROPHONE
        true
        #else
        false
        #endif
    }

    static func deviceKeyScopedGateway(_ gateway: HTMLAppGatewayConfiguration) -> HTMLAppGatewayConfiguration {
        deviceKeyScopedGateway(gateway, supportsAudioLevel: supportsAudioLevel)
    }

    static func deviceKeyScopedGateway(
        _ gateway: HTMLAppGatewayConfiguration,
        supportsAudioLevel: Bool
    ) -> HTMLAppGatewayConfiguration {
        guard gateway.baseURL.lowercased() == DrelGatewayConfiguration.official.baseURL.lowercased(),
              let key = OfficialPushIdentityStore.shared.currentIfAvailable(), !key.isEmpty,
              var components = URLComponents(string: gateway.manifestPath) else {
            return gateway
        }
        components.query = nil
        var queryItems = [URLQueryItem(name: "key", value: key)]
        // Gate new catalog actions so older clients never decode unsupported entries.
        if supportsAudioLevel {
            queryItems.append(URLQueryItem(name: "supportedActions", value: "audioLevel"))
        }
        components.queryItems = queryItems
        guard let scoped = components.string else { return gateway }
        return HTMLAppGatewayConfiguration(
            id: gateway.id,
            name: gateway.name,
            baseURL: gateway.baseURL,
            healthPath: gateway.healthPath,
            manifestPath: scoped,
            publicKeyID: gateway.publicKeyID,
            publicKey: gateway.publicKey
        )
    }

    private func finish(_ completion: @escaping (Bool) -> Void, accepted: Bool) {
        DispatchQueue.main.async {
            completion(accepted)
        }
    }
}
