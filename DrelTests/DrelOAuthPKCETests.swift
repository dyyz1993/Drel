import XCTest
@testable import Drel

final class DrelOAuthPKCETests: XCTestCase {
    func testGeneratesRFC7636VerifierAndChallenge() throws {
        let bytes = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) })
        let pair = try DrelOAuthPKCE.generate { _ in bytes }
        XCTAssertEqual(pair.verifier.count, 43)
        XCTAssertEqual(pair.method, "S256")
        XCTAssertEqual(
            DrelOAuthPKCE.base64URL(Data(SHA256.hash(data: Data(pair.verifier.utf8)))),
            pair.challenge
        )
        XCTAssertFalse(pair.verifier.contains("="))
        XCTAssertFalse(pair.challenge.contains("+"))
    }

    func testRejectsRandomSourceFailure() {
        XCTAssertThrowsError(try DrelOAuthPKCE.generate { _ in throw DrelOAuthPKCEError.generationFailed })
    }
}

import CryptoKit
