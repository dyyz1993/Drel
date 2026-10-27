import CryptoKit
import XCTest
@testable import Drel

final class ApprovalIdentityTests: XCTestCase {
    func testAssertionBindsRequestTicketAndAction() throws {
        let identity = ApprovalIdentity(privateKey: Curve25519.Signing.PrivateKey())
        let ticket = "opaque-ticket"
        let assertion = identity.assertion(
            requestID: "apr_123",
            ticket: ticket,
            actionID: "approve"
        )
        let parts = assertion.split(separator: ".")
        XCTAssertEqual(parts.count, 3)

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        let signature = try XCTUnwrap(base64URLDecode(String(parts[2])))
        XCTAssertTrue(identity.privateKey.publicKey.isValidSignature(signature, for: signingInput))

        let payloadData = try XCTUnwrap(base64URLDecode(String(parts[1])))
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )
        XCTAssertEqual(payload["requestId"] as? String, "apr_123")
        XCTAssertEqual(payload["ticketHash"] as? String, ApprovalIdentity.ticketHash(ticket))
        XCTAssertEqual(payload["actionId"] as? String, "approve")
        XCTAssertEqual(payload["sub"] as? String, identity.subject)
        XCTAssertEqual(payload["iss"] as? String, "drel")
        XCTAssertEqual(payload["aud"] as? String, "drel-approval")
    }

    func testPublicKeyIsSPKIPEM() {
        let identity = ApprovalIdentity(privateKey: Curve25519.Signing.PrivateKey())
        XCTAssertTrue(identity.publicKeyPEM.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        XCTAssertTrue(identity.publicKeyPEM.hasSuffix("-----END PUBLIC KEY-----"))
        XCTAssertTrue(identity.subject.hasPrefix("drel:"))
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }
}
