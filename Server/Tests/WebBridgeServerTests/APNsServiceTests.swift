import Foundation
import Testing
@testable import WebBridgeServer

@Suite("APNs delivery policy")
struct APNsServiceTests {
  @Test("positive ttl maps to bounded APNs expiration")
  func positiveTTLMapsToBoundedAPNsExpiration() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let expiration = APNsService.testableExpiration(
      after: 31 * 24 * 3600,
      from: now
    )

    #expect(expiration == 1_800_000_000 + APNsService.maximumAPNsExpiration)
  }

  @Test("non-positive ttl omits APNs expiration")
  func nonPositiveTTLOmitsAPNsExpiration() {
    #expect(APNsService.testableExpiration(after: 0, from: Date()) == nil)
    #expect(APNsService.testableExpiration(after: -1, from: Date()) == nil)
  }
}
