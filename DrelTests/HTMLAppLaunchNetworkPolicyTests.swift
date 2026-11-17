import XCTest
@testable import Drel
import WebBridgeKit

final class HTMLAppLaunchNetworkPolicyTests: XCTestCase {
    func testUnknownColdStartKeepsOnlinePolicyAndDoesNotRelax() {
        let policy = DrelHTMLAppLaunchSupport.networkPolicy(
            isConnectivityKnown: false,
            isConnected: false
        )
        XCTAssertEqual(policy, .online)
    }

    func testConfirmedOfflineArmsVerifiedFallback() {
        let policy = DrelHTMLAppLaunchSupport.networkPolicy(
            isConnectivityKnown: true,
            isConnected: false
        )
        XCTAssertEqual(policy, .offlineFallback)
    }

    func testConfirmedOnlineKeepsCurrentUpdatePolicy() {
        let policy = DrelHTMLAppLaunchSupport.networkPolicy(
            isConnectivityKnown: true,
            isConnected: true
        )
        XCTAssertEqual(policy, .online)
    }
}
