import Foundation
import WebBridgeKit

struct ApprovalResponseResult: Decodable {
    let requestID: String
    let state: String
    let revision: Int

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case state, revision
    }
}

enum ApprovalResponseClientError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case rejected(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "审批服务器或设备 Key 未配置"
        case .invalidResponse:
            return "审批服务器返回了无效响应"
        case .rejected(_, let message):
            return message
        }
    }
}

final class ApprovalResponseClient {
    private let baseURL: String
    private let deviceKey: String
    private let session: URLSession
    private let identity: ApprovalIdentity

    init(
        baseURL: String,
        deviceKey: String,
        session: URLSession = .shared,
        identity: ApprovalIdentity = ApprovalIdentityKeyStore.shared.identity
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.deviceKey = deviceKey
        self.session = session
        self.identity = identity
    }

    func respond(
        requestID: String,
        actionID: String,
        expectedRevision: Int,
        values: [String: String],
        completion: @escaping (Result<ApprovalResponseResult, Error>) -> Void
    ) {
        let pathSegmentCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard !deviceKey.isEmpty,
              let encodedID = requestID.addingPercentEncoding(withAllowedCharacters: pathSegmentCharacters),
              let url = URL(string: "\(baseURL)/api/v1/approvals/\(encodedID)/respond") else {
            complete(completion, with: .failure(ApprovalResponseClientError.invalidConfiguration))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "actionId": actionID,
            "expectedRevision": expectedRevision,
            "values": values
        ])

        session.dataTask(with: request) { data, response, error in
            if let error {
                self.complete(completion, with: .failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data else {
                self.complete(completion, with: .failure(ApprovalResponseClientError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = object?["message"] as? String
                    ?? object?["error"] as? String
                    ?? "审批提交失败（HTTP \(response.statusCode)）"
                self.complete(completion, with: .failure(
                    ApprovalResponseClientError.rejected(statusCode: response.statusCode, message: message)
                ))
                return
            }
            do {
                self.complete(
                    completion,
                    with: .success(try JSONDecoder().decode(ApprovalResponseResult.self, from: data))
                )
            } catch {
                self.complete(completion, with: .failure(error))
            }
        }.resume()
    }

    func respond(
        submit: MessageApprovalSubmit,
        requestID: String,
        actionID: String,
        expectedRevision: Int,
        values: [String: String],
        completion: @escaping (Result<ApprovalResponseResult, Error>) -> Void
    ) {
        guard let url = URL(string: submit.url),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              !submit.ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            complete(completion, with: .failure(ApprovalResponseClientError.invalidConfiguration))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "ticket": submit.ticket,
            "requestId": requestID,
            "actionId": actionID,
            "expectedRevision": expectedRevision,
            "values": values,
            "actorAssertion": identity.assertion(
                requestID: requestID,
                ticket: submit.ticket,
                actionID: actionID
            )
        ])

        session.dataTask(with: request) { data, response, error in
            if let error {
                self.complete(completion, with: .failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data else {
                self.complete(completion, with: .failure(ApprovalResponseClientError.invalidResponse))
                return
            }
            guard (200...299).contains(response.statusCode) else {
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = object?["message"] as? String
                    ?? object?["error"] as? String
                    ?? "审批提交失败（HTTP \(response.statusCode)）"
                self.complete(completion, with: .failure(
                    ApprovalResponseClientError.rejected(statusCode: response.statusCode, message: message)
                ))
                return
            }
            do {
                self.complete(
                    completion,
                    with: .success(try JSONDecoder().decode(ApprovalResponseResult.self, from: data))
                )
            } catch {
                self.complete(completion, with: .failure(error))
            }
        }.resume()
    }

    private func complete(
        _ completion: @escaping (Result<ApprovalResponseResult, Error>) -> Void,
        with result: Result<ApprovalResponseResult, Error>
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
