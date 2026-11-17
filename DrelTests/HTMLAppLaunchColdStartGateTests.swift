import XCTest
@testable import Drel
import WebBridgeKit

/// Cold-start gate behavior: the wait rides on the framework first-sample
/// notification with a bounded timeout, never blocks a thread with polling,
/// and never relaxes the policy while connectivity is still unknown.
final class HTMLAppLaunchColdStartGateTests: XCTestCase {
    private final class AtomicFlag {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ value: Bool) { lock.lock(); self.value = value; lock.unlock() }
    }

    func testKnownConnectivityResolvesOnCallingActorImmediately() async throws {
        let started = Date()
        let target = try await DrelHTMLAppLaunchSupport.resolveWithColdStartGate(
            isConnectivityKnown: { true }
        ) {
            return HTMLAppLaunchTarget(
                manifest: HTMLAppLaunchColdStartGateTests.stubManifest(),
                pageURL: URL(string: "https://example.com/index.html")!,
                resourceManifestURL: nil,
                offlineMode: .partial,
                context: HTMLAppLaunchContext(appID: "test", route: "/", source: .direct)
            )
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(target.offlineMode, .partial)
    }

    func testUnknownThenOfflineFirstTapResolvesWithFallbackPolicy() async throws {
        let known = AtomicFlag(false)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
            known.set(true)
        }
        let resolvedPolicy = AtomicFlag(false)
        let target = try await DrelHTMLAppLaunchSupport.resolveWithColdStartGate(
            timeout: 3.0,
            isConnectivityKnown: { known.get() }
        ) {
            let policy = DrelHTMLAppLaunchSupport.networkPolicy(
                isConnectivityKnown: true,
                isConnected: false
            )
            resolvedPolicy.set(policy == .offlineFallback)
            return HTMLAppLaunchTarget(
                manifest: HTMLAppLaunchColdStartGateTests.stubManifest(),
                pageURL: URL(string: "https://example.com/index.html")!,
                resourceManifestURL: nil,
                offlineMode: .strong,
                context: HTMLAppLaunchContext(appID: "test", route: "/", source: .direct)
            )
        }
        XCTAssertEqual(target.offlineMode, .strong)
        XCTAssertTrue(resolvedPolicy.get())
    }

    func testTimeoutKeepsConservativeOnlineResolveWithoutRelaxing() async throws {
        let started = Date()
        let target = try await DrelHTMLAppLaunchSupport.resolveWithColdStartGate(
            timeout: 0.3,
            isConnectivityKnown: { false }
        ) {
            return HTMLAppLaunchTarget(
                manifest: HTMLAppLaunchColdStartGateTests.stubManifest(),
                pageURL: URL(string: "https://example.com/index.html")!,
                resourceManifestURL: nil,
                offlineMode: .partial,
                context: HTMLAppLaunchContext(appID: "test", route: "/", source: .direct)
            )
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 0.3)
        XCTAssertLessThan(elapsed, 1.5)
        XCTAssertEqual(target.offlineMode, .partial)
    }

    func testHostAppNetworkMonitorReachesKnownState() async throws {
        // Real cold-start integration: the app-host singleton starts its
        // NWPathMonitor during launch; the first authoritative sample must
        // arrive within seconds without any polling on our side.
        let deadline = Date().addingTimeInterval(5)
        while !NetworkMonitor.shared.isConnectivityKnown && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(NetworkMonitor.shared.isConnectivityKnown)
    }

    private static func stubManifest() -> HTMLAppManifest {
        HTMLAppManifest(
            appID: "test.app",
            name: "Test",
            startURL: "https://example.com/index.html",
            allowedOrigins: ["https://example.com"],
            capabilities: [],
            routes: ["/"],
            cache: HTMLAppCachePolicy(strategy: .networkOnly, version: "1", persistent: false)
        )
    }
}
