import XCTest
@testable import Drel

/// Guards the regression behind the `/ws/stream` 404 storm: the relay used to
/// treat a 404 as a stream that ended, reconnect every 3 seconds, and reset
/// its own attempt counter on each `connect()` so the cap never applied.
final class PushRelayRetryPolicyTests: XCTestCase {

    func testSuccessfulStreamIsTheOnlyOutcomeThatResetsBackoff() {
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 200), .connected)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 204), .connected)
    }

    func testMissingStreamRouteIsUnsupported() {
        // The observed production failure: the Bark-compatible server has no
        // SSE route, so `/ws/stream` resolves to a push for device key "ws".
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 404), .unsupported)
        // A wrong capability or a blocked origin is equally not worth polling.
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 401), .unsupported)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 403), .unsupported)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 498), .unsupported)
    }

    func testServerAndRateLimitFailuresAreTransient() {
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 429), .transient)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 503), .transient)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 500), .transient)
        XCTAssertEqual(PushRelayRetryPolicy.outcome(statusCode: 408), .transient)
    }

    func testBackoffStartsSlowAndIsCapped() {
        // The very first retry must not be the old ~3 second hot loop.
        XCTAssertEqual(PushRelayRetryPolicy.delay(forAttempt: 1), 5)
        XCTAssertEqual(PushRelayRetryPolicy.delay(forAttempt: 2), 10)
        XCTAssertEqual(PushRelayRetryPolicy.delay(forAttempt: 3), 20)
        // Never exceeds the ceiling however long the outage lasts.
        XCTAssertEqual(PushRelayRetryPolicy.delay(forAttempt: 7), 300)
        XCTAssertEqual(PushRelayRetryPolicy.delay(forAttempt: 40), 300)
    }

    func testBackoffIsMonotonicAndBounded() {
        var previous: TimeInterval = 0
        for attempt in 1...64 {
            let delay = PushRelayRetryPolicy.delay(forAttempt: attempt)
            XCTAssertGreaterThanOrEqual(delay, previous, "attempt \(attempt) went backwards")
            XCTAssertLessThanOrEqual(delay, PushRelayRetryPolicy.maxDelay)
            previous = delay
        }
    }

    /// A sustained outage (server restart, captive portal) settles at the
    /// ceiling: at most ~12 requests/hour rather than one every 3 seconds.
    func testSustainedOutageTrafficIsBounded() {
        let requestsPerHour = 3600 / PushRelayRetryPolicy.maxDelay
        XCTAssertLessThanOrEqual(requestsPerHour * PushRelayRetryPolicy.maxDelay, 3600)
        XCTAssertLessThanOrEqual(requestsPerHour, 12)
    }
}
