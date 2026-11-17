import WebBridgeKit
import Foundation

/// Single wiring point for HTML app launch resolution in Drel.
///
/// The offline stale-package fallback is armed with the official gateway
/// trust anchor and only engages while NetworkMonitor reports no usable
/// network. Online launches keep the existing update policy: a package whose
/// version trails the current signed manifest keeps resolving to the network
/// page so the newer version installs on the next successful load.
enum DrelHTMLAppLaunchSupport {
    /// Nil when the official gateway has no configured public key: without a
    /// cryptographic trust anchor an old package can never be independently
    /// proven, so the fallback must stay disabled.
    static var signatureVerifier: ((HTMLAppManifest) -> Bool)? {
        #if DEBUG
        if let override = signatureVerifierOverride { return override }
        #endif
        return officialSignatureVerifier
    }

    private static let officialSignatureVerifier =
        HTMLAppGatewayOnboardingService.offlineFallbackSignatureVerifier(
            publicKeyID: DrelGatewayConfiguration.official.publicKeyID,
            publicKey: DrelGatewayConfiguration.official.publicKey
        )

    #if DEBUG
    /// Test-target-only injection (compiled out of release builds): swaps the
    /// trust anchor for the E2E fixture signing key. Production releases
    /// always verify with the official gateway public key.
    static var signatureVerifierOverride: ((HTMLAppManifest) -> Bool)?
    #endif

    /// True once NetworkMonitor delivered its first authoritative sample.
    static var isConnectivityKnown: Bool {
        NetworkMonitor.shared.isConnectivityKnown
    }

    /// Confirmed offline only; an unknown cold-start sample is never treated
    /// as offline.
    static var isConfirmedOffline: Bool {
        #if DEBUG
        if let override = isConfirmedOfflineOverride { return override }
        #endif
        return isConnectivityKnown && !NetworkMonitor.shared.isConnected
    }

    #if DEBUG
    /// Test-target-only injection (compiled out of release builds). Lets
    /// end-to-end tests simulate a confirmed offline condition without
    /// touching real device networking.
    static var isConfirmedOfflineOverride: Bool?
    #endif

    static func makeResolver(trustRegistry: HTMLAppTrustRegistry) -> HTMLAppLaunchResolver {
        HTMLAppLaunchResolver(
            trustRegistry: trustRegistry,
            signatureVerifier: signatureVerifier
        )
    }

    static var networkPolicy: HTMLAppLaunchNetworkPolicy {
#if DEBUG
        if let override = isConfirmedOfflineOverride {
            return override ? .offlineFallback : .online
        }
#endif
        return networkPolicy(
            isConnectivityKnown: NetworkMonitor.shared.isConnectivityKnown,
            isConnected: NetworkMonitor.shared.isConnected
        )
    }

    /// Non-blocking async variant. Suspends on the first authoritative
    /// connectivity sample (bounded by timeout; the wait rides on the
    /// framework first-sample notification, no polling) instead of parking
    /// the calling thread, then resolves under the three-state policy: an
    /// unknown sample that timed out keeps the conservative online policy.
    static func resolveWithColdStartGate(
        timeout: TimeInterval = 2.0,
        isConnectivityKnown overrideKnown: (() -> Bool)? = nil,
        resolve: () throws -> HTMLAppLaunchTarget
    ) async throws -> HTMLAppLaunchTarget {
        let known = overrideKnown ?? { NetworkMonitor.shared.connectivitySnapshot().isConnectivityKnown }
        if known() {
            return try resolve()
        }
        if overrideKnown != nil {
            // Test injection has no notification source; bounded light wait.
            let deadline = Date().addingTimeInterval(timeout)
            while !known() && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } else {
            await NetworkMonitor.shared.waitFirstConnectivitySample(timeout: timeout)
        }
        return try resolve()
    }

    /// Three-state policy. Unknown connectivity (cold start before the first
    /// NWPathMonitor update) must never be treated as a confirmed offline
    /// condition, so it keeps the online policy: a newer signed manifest
    /// stays preferred and nothing is relaxed. A confirmed offline state is
    /// the only condition that arms the verified stale-package fallback.
    static func networkPolicy(
        isConnectivityKnown: Bool,
        isConnected: Bool
    ) -> HTMLAppLaunchNetworkPolicy {
        guard isConnectivityKnown else { return .online }
        return isConnected ? .online : .offlineFallback
    }

    // MARK: - Duplicate launch protection (same target + same source identity)

    /// A structured slot key: Hashable composition instead of string
    /// concatenation, so distinct parameter sets can never collide through a
    /// separator that also appears inside a value. Parameter values are
    /// normalized with a type marker (Int 1, String "1" and Bool true all
    /// encode differently), and the dictionary's synthesized Hashable
    /// equality covers unordered but identical content.
    /// Every real launch entry passes string-valued parameters only
    /// (MessagePayload.userInfo, HTMLAppPushEnvelope.parameters and
    /// DrelExternalAppLink.parameters are all [String: String]), so the key
    /// stores them verbatim: the synthesized Hashable/Equatable over the
    /// dictionary is unambiguous, and non-string payloads (Bool/Int/arrays)
    /// are excluded at compile time instead of negotiated in encoding.
    struct LaunchSlotKey: Hashable {
        var appID: String
        var route: String
        var normalizedParameters: [String: String]
        var sourceID: String

        init(appID: String, route: String, parameters: [String: String], sourceID: String) {
            self.appID = appID
            self.route = route
            self.sourceID = sourceID
            self.normalizedParameters = parameters
        }

    }

    /// Opaque ownership token returned by acquire; release only removes the
    /// slot when the presented token still owns it, so a slow holder whose
    /// slot already expired (TTL) and was re-acquired by someone else cannot
    /// release the new owner's slot through its deferred cleanup.
    struct LaunchSlotOwner {
        let key: LaunchSlotKey
        let id: UUID
    }

    private static let launchSlotLock = NSLock()
    private static var launchSlotHeld: [LaunchSlotKey: (ownerID: UUID, heldSince: Date)] = [:]

    /// Safety valve for a hung holder: slots older than this become
    /// reacquirable. The normal lifetime is bounded by the 2 s gate plus
    /// synchronous resolve/present work, so 10 s leaves a wide margin.
    static var launchSlotTTL: TimeInterval = 10

    /// Returns an owner token when the caller newly owns the launch slot for
    /// this exact target+intent. Nil means an identical attempt is already in
    /// flight (or acquired after this one's slot expired) and must be waited
    /// out instead of duplicated. Thread-safe.
    static func acquireLaunchSlot(
        appID: String,
        route: String,
        parameters: [String: String],
        sourceID: String
    ) -> LaunchSlotOwner? {
        let key = LaunchSlotKey(appID: appID, route: route, parameters: parameters, sourceID: sourceID)
        launchSlotLock.lock()
        defer { launchSlotLock.unlock() }
        let now = Date()
        launchSlotHeld = launchSlotHeld.filter {
            now.timeIntervalSince($0.value.heldSince) < launchSlotTTL
        }
        guard launchSlotHeld[key] == nil else { return nil }
        launchSlotHeld[key] = (ownerID: UUID(), heldSince: now)
        return LaunchSlotOwner(key: key, id: launchSlotHeld[key]!.ownerID)
    }

    /// Releases the slot only if the presented token still owns it. A stale
    /// owner (its slot expired and was reclaimed by a new holder) releases
    /// nothing. Thread-safe.
    static func releaseLaunchSlot(owner: LaunchSlotOwner) {
        launchSlotLock.lock()
        defer { launchSlotLock.unlock() }
        guard let current = launchSlotHeld[owner.key], current.ownerID == owner.id else { return }
        launchSlotHeld.removeValue(forKey: owner.key)
    }

    /// Test-only cleanup for the process-wide slot registry.
    static func resetLaunchSlotsForTesting() {
        launchSlotLock.lock()
        defer { launchSlotLock.unlock() }
        launchSlotHeld.removeAll()
    }
}
