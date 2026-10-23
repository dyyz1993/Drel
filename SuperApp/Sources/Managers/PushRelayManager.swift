//
//  PushRelayManager.swift
//  SuperApp
//

import Foundation
import UserNotifications
import WebBridgeKit

struct SSEPushPayload {
    let id: String
    let title: String
    let body: String
    let subtitle: String?
    let url: String
    let sound: String?
    let badge: Int
    let group: String?
    let category: String?
    let thread: String?
    let appid: String?
    let route: String?
    let mode: String?
    let display: String?
    let icon: String?
    let markdownBody: String?
    let level: String?
    let image: String?
    let action: [String: Any]?
    let copy: String?
    let autoCopy: String?
    let ciphertext: String?
    let iv: String?
    let call: String?
    let verificationCode: String?
    let expiresAt: String?
    let ttl: Any?
    let isDeleted: Any?
    let actionState: String?
    let requestID: String?
    let contentType: String?
    let qrPayload: String?
    let statePath: String?
    let revision: Any?
    let params: [String: Any]?
    let presentation: String?
    let approval: [String: Any]?

    init(data: [String: Any]) {
        id = data["id"] as? String ?? UUID().uuidString
        title = data["title"] as? String ?? "通知"
        body = data["body"] as? String ?? ""
        subtitle = data["subtitle"] as? String
        url = data["url"] as? String ?? ""
        sound = data["sound"] as? String
        badge = data["badge"] as? Int ?? 0
        group = data["group"] as? String
        category = data["category"] as? String
        thread = data["threadId"] as? String ?? data["thread"] as? String
        appid = data["appId"] as? String ?? data["appid"] as? String
        route = data["route"] as? String
        mode = data["mode"] as? String
        display = data["display"] as? String
        icon = data["icon"] as? String
        markdownBody = data["markdown"] as? String
        level = data["level"] as? String
        image = data["image"] as? String
        action = data["action"] as? [String: Any]
        copy = data["copy"] as? String
        autoCopy = data["autoCopy"] as? String
        ciphertext = data["ciphertext"] as? String
        iv = data["iv"] as? String
        call = data["call"] as? String
        verificationCode = data["verificationCode"] as? String
        expiresAt = data["expiresAt"] as? String
        ttl = data["ttl"]
        isDeleted = data["delete"]
        actionState = data["state"] as? String ?? data["actionState"] as? String
        requestID = data["requestId"] as? String
        contentType = data["type"] as? String ?? data["contentType"] as? String
        qrPayload = data["qrPayload"] as? String
        statePath = data["statePath"] as? String
        revision = data["revision"]
        params = data["params"] as? [String: Any]
        presentation = data["presentation"] as? String
        approval = data["approval"] as? [String: Any]
    }
}

final class PushRelayManager: NSObject, URLSessionDataDelegate {
    static let shared = PushRelayManager()

    private static let defaultBaseURL = "https://api.drel.app"

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var reconnectTimer: Timer?
    private var isConnected = false
    private var reconnectAttempts: Int = 0
    private var buffer = ""
    /// Base URL of the stream currently in flight, used to attribute a
    /// response to the host that produced it.
    private var currentBaseURL: String?

    /// Base URL whose server answered the stream route with a "this endpoint
    /// does not exist" status. The relay is an enhancement (APNs plus the
    /// Notification Service Extension already record pushes), so an
    /// unsupported endpoint stops the relay instead of being polled forever.
    /// Stored per host so switching gateway re-arms the relay.
    private var unsupportedBaseURL: String?

    /// Read per connect so switching gateway while the app runs takes effect.
    private var baseURL: String {
        ServerConfigManager.shared.getActiveBaseURL() ?? Self.defaultBaseURL
    }

    private override init() { super.init() }

    func connect() {
        // Relay state is main-confined: the URLSession delegate queue and the
        // reconnect timer both run on main. AppDelegate launches `connect()`
        // from a utility queue, so normalize onto main before touching it.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.connect() }
            return
        }
        let activeBaseURL = baseURL
        guard unsupportedBaseURL != activeBaseURL else { return }
        guard !isConnected else { return }
        guard let url = URL(string: activeBaseURL + "/ws/stream") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(INT_MAX)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        buffer = ""
        session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
        isConnected = true
        currentBaseURL = activeBaseURL
        #if !DREL_CONTAINER_ONLY
        print("[PushRelay] SSE connecting: \(url)")
        #endif
    }

    func disconnect() {
        reconnectTimer?.invalidate(); reconnectTimer = nil
        dataTask?.cancel(); dataTask = nil
        session?.invalidateAndCancel(); session = nil
        isConnected = false; buffer = ""
        #if !DREL_CONTAINER_ONLY
        print("[PushRelay] Disconnected")
        #endif
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch PushRelayRetryPolicy.outcome(statusCode: statusCode) {
        case .connected:
            // Only a real 2xx stream resets the backoff. Resetting in
            // `connect()` instead (the previous behaviour) made the attempt
            // counter unreachable, so the relay retried a 404 every 3 seconds.
            reconnectAttempts = 0
        case .unsupported:
            // Attribute the rejection to the host we actually asked. Leave
            // the marker nil if that is unknown, so the relay falls back to
            // plain backoff instead of parking on the wrong host.
            unsupportedBaseURL = currentBaseURL
            // Do not stream the error body; completing the task immediately
            // is what parks the relay instead of re-downloading a 404.
            completionHandler(.cancel)
            #if !DREL_CONTAINER_ONLY
            print("[PushRelay] SSE response, status: \(statusCode) (unsupported)")
            #endif
            return
        case .transient:
            break
        }
        #if !DREL_CONTAINER_ONLY
        print("[PushRelay] SSE response, status: \(statusCode)")
        #endif
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        while let range = buffer.range(of: "\n\n") {
            let eventText = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            processSSE(eventText)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        #if !DREL_CONTAINER_ONLY
        if let error = error { print("[PushRelay] Stream ended: \(error.localizedDescription)") }
        #endif
        scheduleReconnect()
    }

    // MARK: - SSE Processing

    private func processSSE(_ text: String) {
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard let data = jsonStr.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            #if !DREL_CONTAINER_ONLY
            if type == "connected" { print("[PushRelay] SSE connected"); continue }
            #endif
            guard type == "push", let pushData = json["data"] as? [String: Any] else { continue }
            let payload = SSEPushPayload(data: pushData)
            showLocalNotification(payload)
        }
    }

    // MARK: - Notification Delivery

    private func showLocalNotification(_ p: SSEPushPayload) {
        let content = UNMutableNotificationContent()
        content.title = p.title

        if let markdown = p.markdownBody, !markdown.isEmpty {
            content.body = p.body.isEmpty ? p.title : p.body
        } else {
            content.body = p.body
        }

        if let subtitle = p.subtitle { content.subtitle = subtitle }

        if p.mode == "silent" || p.mode == "passive" {
            content.sound = nil
        } else if let sound = p.sound, !sound.isEmpty {
            if sound == "default" {
                content.sound = UNNotificationSound.default
            } else {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
            }
        } else {
            content.sound = UNNotificationSound.default
        }

        if p.badge > 0 { content.badge = NSNumber(value: p.badge) }

        var userInfo: [String: Any] = ["channel": "ws-push"]
        if !p.url.isEmpty { userInfo["url"] = p.url }
        if let appid = p.appid { userInfo["appid"] = appid }
        if let route = p.route { userInfo["route"] = route }
        if let mode = p.mode { userInfo["mode"] = mode }
        if let display = p.display { userInfo["display"] = display }
        if let md = p.markdownBody, !md.isEmpty { userInfo["markdown"] = md }
        if let level = p.level { userInfo["level"] = level }
        if let image = p.image { userInfo["image"] = image }
        if let action = p.action { userInfo["action"] = action }
        if let copy = p.copy { userInfo["copy"] = copy }
        if let autoCopy = p.autoCopy { userInfo["autoCopy"] = autoCopy }
        if let ciphertext = p.ciphertext { userInfo["ciphertext"] = ciphertext }
        if let iv = p.iv { userInfo["iv"] = iv }
        if let call = p.call { userInfo["call"] = call }
        userInfo["id"] = p.id
        if let verificationCode = p.verificationCode { userInfo["verificationCode"] = verificationCode }
        if let expiresAt = p.expiresAt { userInfo["expiresAt"] = expiresAt }
        if let ttl = p.ttl { userInfo["ttl"] = ttl }
        if let isDeleted = p.isDeleted { userInfo["delete"] = isDeleted }
        if let actionState = p.actionState { userInfo["actionState"] = actionState }
        if let requestID = p.requestID { userInfo["requestId"] = requestID }
        if let contentType = p.contentType { userInfo["contentType"] = contentType }
        if let qrPayload = p.qrPayload { userInfo["qrPayload"] = qrPayload }
        if let statePath = p.statePath { userInfo["statePath"] = statePath }
        if let revision = p.revision { userInfo["revision"] = revision }
        if let params = p.params { userInfo["params"] = params }
        if let presentation = p.presentation { userInfo["presentation"] = presentation }
        if let approval = p.approval { userInfo["approval"] = approval }
        content.userInfo = userInfo

        let threadId = p.thread ?? p.group
        if let tid = threadId, !tid.isEmpty {
            content.threadIdentifier = tid
            content.summaryArgument = p.title
        }
        if let category = p.category { content.categoryIdentifier = category }

        if let iconStr = p.icon, !iconStr.isEmpty, let iconURL = URL(string: iconStr) {
            deliverWithIcon(content: content, iconURL: iconURL, identifier: p.id)
        } else {
            deliverNow(content: content, identifier: p.id)
        }
    }

    private func deliverWithIcon(content: UNMutableNotificationContent, iconURL: URL, identifier: String) {
        URLSession.shared.downloadTask(with: iconURL) { tempURL, _, error in
            let finalContent = content
            defer { self.deliverNow(content: finalContent, identifier: identifier) }
            guard let tempURL = tempURL, error == nil else { return }
            let ext = iconURL.pathExtension.isEmpty ? "png" : iconURL.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("notif_icon_\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                if let att = try? UNNotificationAttachment(identifier: "icon", url: dest, options: nil) {
                    finalContent.attachments = [att]
                }
            } catch {
                #if !DREL_CONTAINER_ONLY
                print("[PushRelay] Icon attach failed: \(error)")
                #endif
            }
        }.resume()
    }

    private func deliverNow(content: UNMutableNotificationContent, identifier: String) {
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err = err {
                #if !DREL_CONTAINER_ONLY
                print("[PushRelay] Failed: \(err)")
                #endif
            } else {
                #if !DREL_CONTAINER_ONLY
                print("[PushRelay] [OK] Shown: \(content.title)")
                #endif
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        isConnected = false
        guard unsupportedBaseURL != currentBaseURL else {
            // The server has no stream route (or rejected this one
            // permanently). Stop for this launch; polling it produced
            // hundreds of thousands of 404s in the access log.
            #if !DREL_CONTAINER_ONLY
            print("[PushRelay] SSE endpoint unsupported; relay disabled")
            #endif
            disconnect(); return
        }
        // Transient failures keep retrying at the capped interval so a server
        // restart does not silently disable the relay until the next launch.
        // The cap keeps that to a few requests per hour instead of a hot loop.
        reconnectAttempts += 1
        let delay = PushRelayRetryPolicy.delay(forAttempt: reconnectAttempts)
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.dataTask?.cancel(); self.dataTask = nil
            self.session?.invalidateAndCancel(); self.session = nil
            self.connect()
        }
        #if !DREL_CONTAINER_ONLY
        print("[PushRelay] Reconnecting in \(delay)s (attempt \(reconnectAttempts))")
        #endif
    }
}

/// Retry classification for the optional `/ws/stream` SSE relay.
///
/// The relay is an enhancement, not a delivery path: APNs plus the
/// Notification Service Extension already record background pushes into the
/// Inbox, and foreground pushes present through `willPresent`. A server that
/// has no SSE route must therefore be treated as unsupported and never
/// polled again. Before this policy existed a 404 was retried every ~3
/// seconds forever (the attempt cap was unreachable because `connect()`
/// reset the counter), which filled the server access log and kept the radio
/// awake while the app was open.
enum PushRelayRetryPolicy {
    enum Outcome: Equatable {
        /// The stream opened; reset the backoff.
        case connected
        /// The endpoint does not exist on this server; stop retrying.
        case unsupported
        /// A temporary failure worth retrying with backoff.
        case transient
    }

    /// Delay before the first transient retry.
    static let baseDelay: TimeInterval = 5
    /// Ceiling for the exponential backoff.
    static let maxDelay: TimeInterval = 300

    static func outcome(statusCode: Int) -> Outcome {
        switch statusCode {
        case 200..<300: return .connected
        case 408, 425, 429, 500..<600: return .transient
        default: return .unsupported
        }
    }

    /// Exponential backoff, capped. `attempt` is 1-based.
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return baseDelay }
        return min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
    }
}
