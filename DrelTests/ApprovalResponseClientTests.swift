import XCTest
import WebBridgeKit
@testable import Drel

final class ApprovalResponseClientTests: XCTestCase {
    override func tearDown() {
        ApprovalURLProtocolStub.handler = nil
        ApprovalURLProtocolStub.requests = []
        super.tearDown()
    }

    func testSubmitPostsDrelBodyToExactThirdPartyURL() throws {
        let session = makeSession()
        ApprovalURLProtocolStub.handler = { _ in
            (200, #"{"requestId":"request-1","state":"approved","revision":2}"#)
        }

        let result = try respond(
            using: ApprovalResponseClient(
                baseURL: "https://api.drel.app",
                deviceKey: "device-key",
                session: session
            ),
            submit: MessageApprovalSubmit(
                url: "https://approve.xbrowser.dev/api/review",
                ticket: "ticket-abc"
            )
        )

        XCTAssertEqual(result.requestID, "request-1")
        let request = try XCTUnwrap(ApprovalURLProtocolStub.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://approve.xbrowser.dev/api/review")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(bodyData(from: request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["ticket"] as? String, "ticket-abc")
        XCTAssertEqual(object["requestId"] as? String, "request-1")
        XCTAssertEqual(object["actionId"] as? String, "approve")
        XCTAssertEqual(object["expectedRevision"] as? Int, 1)
        XCTAssertEqual((object["values"] as? [String: String])?["reason"], "ship it")
        XCTAssertNil(object["actorAssertion"])
    }

    func testMissingSubmitFallsBackToOfficialRespondEndpoint() throws {
        let session = makeSession()
        ApprovalURLProtocolStub.handler = { _ in
            (200, #"{"requestId":"request-1","state":"approved","revision":2}"#)
        }

        _ = try respond(using: ApprovalResponseClient(
            baseURL: "https://api.drel.app",
            deviceKey: "device-key",
            session: session
        ))

        let request = try XCTUnwrap(ApprovalURLProtocolStub.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.drel.app/api/v1/approvals/request-1/respond"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-key")
        let body = try XCTUnwrap(bodyData(from: request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["ticket"])
    }

    func testSubmitRejectsUnsafeConfigurationBeforeNetwork() {
        for submit in [
            MessageApprovalSubmit(url: "http://approve.xbrowser.dev/api/review", ticket: "ticket"),
            MessageApprovalSubmit(url: "https://", ticket: "ticket"),
            MessageApprovalSubmit(url: "https://approve.xbrowser.dev/api/review", ticket: "   "),
        ] {
            let expectation = expectation(description: "rejected")
            ApprovalResponseClient(
                baseURL: "https://api.drel.app",
                deviceKey: "device-key",
                session: makeSession()
            ).respond(
                submit: submit,
                requestID: "request-1",
                actionID: "approve",
                expectedRevision: 1,
                values: [:]
            ) { result in
                guard case .failure = result else {
                    return XCTFail("unsafe submit configuration must fail")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1)
        }
        XCTAssertTrue(ApprovalURLProtocolStub.requests.isEmpty)
    }

    func testThirdPartyTicketPolicyRemainsServerSide() throws {
        // The client forwards the opaque ticket exactly once and does not invent
        // a local replay/state machine. Expiry, one-time use and revision checks
        // remain the third-party Worker's responsibility.
        let session = makeSession()
        ApprovalURLProtocolStub.handler = { _ in
            (409, #"{"error":"ticket_already_used"}"#)
        }

        let expectation = expectation(description: "conflict")
        ApprovalResponseClient(
            baseURL: "https://api.drel.app",
            deviceKey: "device-key",
            session: session
        ).respond(
            submit: MessageApprovalSubmit(
                url: "https://approve.xbrowser.dev/api/review",
                ticket: "opaque-once"
            ),
            requestID: "request-1",
            actionID: "approve",
            expectedRevision: 1,
            values: [:]
        ) { result in
            guard case .failure(let error as ApprovalResponseClientError) = result,
                  case .rejected(statusCode: 409, message: "ticket_already_used") = error else {
                return XCTFail("expected the Worker's 409 to be surfaced")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(ApprovalURLProtocolStub.requests.count, 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApprovalURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func respond(
        using client: ApprovalResponseClient,
        submit: MessageApprovalSubmit? = nil
    ) throws -> ApprovalResponseResult {
        let expectation = expectation(description: "response")
        var captured: Result<ApprovalResponseResult, Error>?
        let completion: (Result<ApprovalResponseResult, Error>) -> Void = {
            captured = $0
            expectation.fulfill()
        }
        if let submit {
            client.respond(
                submit: submit,
                requestID: "request-1",
                actionID: "approve",
                expectedRevision: 1,
                values: ["reason": "ship it"],
                completion: completion
            )
        } else {
            client.respond(
                requestID: "request-1",
                actionID: "approve",
                expectedRevision: 1,
                values: ["reason": "ship it"],
                completion: completion
            )
        }
        wait(for: [expectation], timeout: 2)
        return try XCTUnwrap(captured).get()
    }
}

private final class ApprovalURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
