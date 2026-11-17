import XCTest
@testable import Drel

/// Regression coverage for the cold-start async window duplicate-launch
/// guard. The slot key is a structured Hashable value (appID, route, a
/// type-marked normalized parameter map, source identity), so distinct
/// parameter sets can never collide via separator characters inside values.
/// A slot release only removes the entry when the caller still owns the
/// owner token, so a slow holder whose slot expired (TTL) and was reclaimed
/// by a new holder cannot release someone else's slot through its deferred
/// cleanup.
final class HTMLAppLaunchSlotTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        func get() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    override func setUp() {
        super.setUp()
        DrelHTMLAppLaunchSupport.resetLaunchSlotsForTesting()
    }

    override func tearDown() {
        DrelHTMLAppLaunchSupport.resetLaunchSlotsForTesting()
        super.tearDown()
    }

    private func acquire(
        _ appID: String, _ route: String, _ parameters: [String: String], _ sourceID: String
    ) -> DrelHTMLAppLaunchSupport.LaunchSlotOwner? {
        DrelHTMLAppLaunchSupport.acquireLaunchSlot(
            appID: appID, route: route, parameters: parameters, sourceID: sourceID
        )
    }

    func testExactDuplicateSuppressedUntilReleased() {
        let first = acquire("app.a", "/home", ["botId": "b1"], "message.m1")
        XCTAssertNotNil(first)
        XCTAssertNil(acquire("app.a", "/home", ["botId": "b1"], "message.m1"))
        DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: first!)
        XCTAssertNotNil(acquire("app.a", "/home", ["botId": "b1"], "message.m1"))
    }

    func testSeparatorCharactersInValuesCannotCauseKeyCollision() {
        // These two parameter sets concatenate identically under naive
        // "k=v;" encoding ("a=1;b=2"); the structured key must treat them as
        // distinct targets.
        let first = acquire("app.a", "/home", ["a": "1;b=2"], "message.m1")
        let second = acquire("app.a", "/home", ["a": "1", "b": "2"], "message.m1")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second, "separator characters inside a value must not collide with a different parameter set")
        let third = acquire("app.a", "/home", ["a": "1", "b|c": "2"], "message.m1")
        XCTAssertNotNil(third, "pipe characters inside values must not collide either")
        let fourth = acquire("app.a", "/home", ["a": "1,b"], "message.m1")
        let fifth = acquire("app.a", "/home", ["a": "1", "b": ""], "message.m1")
        XCTAssertNotNil(fourth, "comma inside one value must not collide")
        XCTAssertNotNil(fifth, "a value that would be produced by splitting another must not collide")
        // Bool / Int / array values cannot reach this guard at all: every
        // real entry passes [String: String] (userInfo / envelope / link
        // parameters), so bridging ambiguity is excluded at compile time.
    }

    func testParameterOrderAndEqualityAreCanonical() {
        let k1 = DrelHTMLAppLaunchSupport.LaunchSlotKey(
            appID: "a", route: "/", parameters: ["a": "1", "b": "2"], sourceID: "s"
        )
        let k2 = DrelHTMLAppLaunchSupport.LaunchSlotKey(
            appID: "a", route: "/", parameters: ["b": "2", "a": "1"], sourceID: "s"
        )
        XCTAssertEqual(k1, k2, "identical parameter content in different insertion order is the same target")
        let k3 = DrelHTMLAppLaunchSupport.LaunchSlotKey(
            appID: "a", route: "/", parameters: ["a": "1", "b": "2", "c": "3"], sourceID: "s"
        )
        XCTAssertNotEqual(k1, k3)
    }

    func testDifferentSourceIdentitySameTargetOpensConcurrently() {
        let params = ["botId": "b1"]
        let first = acquire("app.a", "/home", params, "message.m1")
        let second = acquire("app.a", "/home", params, "message.m2")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second, "different messages targeting the same route are different intents")
    }

    func testConcurrentEntryTasksForSameIntentResolveOnceDuringGateWindow() async throws {
        let resolves = Counter()
        let firstTap = Task { @MainActor in
            guard let owner = DrelHTMLAppLaunchSupport.acquireLaunchSlot(
                appID: "app.vot", route: "/index.html",
                parameters: ["botId": "b1"], sourceID: "catalog.tile1"
            ) else { return false }
            defer { DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: owner) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            resolves.increment()
            return true
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        let secondTap = Task { @MainActor in
            guard DrelHTMLAppLaunchSupport.acquireLaunchSlot(
                appID: "app.vot", route: "/index.html",
                parameters: ["botId": "b1"], sourceID: "catalog.tile1"
            ) != nil else { return false }
            resolves.increment()
            return true
        }
        let first = await firstTap.value
        let second = await secondTap.value
        XCTAssertTrue(first)
        XCTAssertFalse(second, "exact duplicate inside the gate window must be suppressed")
        XCTAssertEqual(resolves.get(), 1)
        let reopened = acquire("app.vot", "/index.html", ["botId": "b1"], "catalog.tile1")
        XCTAssertNotNil(reopened, "after release the entry opens normally again")
    }

    func testSlotReleasedWhenResolveThrows() async throws {
        let attempt = Task { @MainActor () -> DrelHTMLAppLaunchSupport.LaunchSlotOwner? in
            guard let owner = DrelHTMLAppLaunchSupport.acquireLaunchSlot(
                appID: "app.err", route: "/", parameters: [:], sourceID: "message.e1"
            ) else { return nil }
            defer { DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: owner) }
            throw CancellationError()
        }
        let owned = try? await attempt.value
        XCTAssertNil(owned, "the attempt acquired the slot and failed as expected")
        XCTAssertNotNil(
            acquire("app.err", "/", [:], "message.e1"),
            "slot must be freed after the failed resolve"
        )
    }

    func testSlotReleasedOnTaskCancellation() async throws {
        let attempt = Task { @MainActor in
            guard let owner = DrelHTMLAppLaunchSupport.acquireLaunchSlot(
                appID: "app.cancel", route: "/", parameters: [:], sourceID: "push.n1"
            ) else { return false }
            defer { DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: owner) }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch {}
            return true
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        attempt.cancel()
        let cancelledOwned = try await attempt.value
        XCTAssertTrue(cancelledOwned)
        XCTAssertNotNil(
            acquire("app.cancel", "/", [:], "push.n1"),
            "slot must be freed when the attempt is cancelled mid-wait"
        )
    }

    func testExpiredSlotIsReclaimableAndStaleOwnerCannotReleaseNewHolder() async throws {
        DrelHTMLAppLaunchSupport.launchSlotTTL = 0.08
        defer { DrelHTMLAppLaunchSupport.launchSlotTTL = 10 }
        let slow = acquire("app.hung", "/", ["botId": "b1"], "push.h1")
        XCTAssertNotNil(slow, "slow holder acquired the slot")
        try await Task.sleep(nanoseconds: 150_000_000)
        // Past the TTL the slot is reclaimable by a new holder.
        let fresh = acquire("app.hung", "/", ["botId": "b1"], "push.h1")
        XCTAssertNotNil(fresh, "expired slot must be reacquirable")
        // The slow holder's deferred cleanup must not release the new owner.
        DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: slow!)
        XCTAssertNil(
            acquire("app.hung", "/", ["botId": "b1"], "push.h1"),
            "stale owner release must not free the new holder's slot"
        )
        DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: fresh!)
        XCTAssertNotNil(
            acquire("app.hung", "/", ["botId": "b1"], "push.h1"),
            "real owner release frees the slot normally"
        )
    }
}
