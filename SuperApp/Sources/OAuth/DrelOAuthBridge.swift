import Foundation
import UIKit
import WebKit
import WebBridgeKit

public final class DrelOAuthBridgeHandler: NSObject, WKScriptMessageHandler {
    public static let messageHandlerName = "DrelOAuthBridge"
    private let broker: DrelOAuthBroker

    public init(broker: DrelOAuthBroker) {
        self.broker = broker
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let callbackID = (body["callbackId"] as? String) ?? (body["messageId"] as? String),
              ["authorization.request", "authorization.getStatus", "authorization.fetch", "authorization.revoke"].contains(action) else {
            return
        }
        let parameters = body["params"] as? [String: Any] ?? body
        Task { @MainActor in
            await self.handle(action: action, parameters: parameters, callbackID: callbackID, webView: message.webView)
        }
    }

    @MainActor
    private func handle(action: String, parameters: [String: Any], callbackID: String, webView: WKWebView?) async {
        let identity = self.identity(from: webView)
        do {
            let result: [String: Any]
            switch action {
            case "authorization.request":
                let scopes = parameters["scopes"] as? [String] ?? []
                let status = try await broker.authorizationRequest(
                    scopes: scopes,
                    gatewayIdentity: identity.gateway,
                    appID: identity.appID,
                    documentOrigin: identity.origin,
                    pairingRequestID: (parameters["pairingRequestId"] as? String)
                        ?? identity.parameters["pairing_request_id"]
                )
                result = try dictionary(from: status)
            case "authorization.getStatus":
                let status = try broker.status(
                    gatewayIdentity: identity.gateway,
                    appID: identity.appID,
                    documentOrigin: identity.origin
                )
                result = try dictionary(from: status)
            case "authorization.fetch":
                let response = try await broker.fetch(
                    gatewayIdentity: identity.gateway,
                    appID: identity.appID,
                    documentOrigin: identity.origin,
                    request: parameters
                )
                result = [
                    "status": response.status,
                    "headers": response.headers,
                    "bodyType": response.bodyType,
                    "body": bodyValue(response.body)
                ]
            case "authorization.revoke":
                try await broker.revoke(
                    gatewayIdentity: identity.gateway,
                    appID: identity.appID,
                    documentOrigin: identity.origin
                )
                result = ["status": "revoked"]
            default:
                throw DrelOAuthError.invalidRequest("unknown action")
            }
            send(["success": true].merging(result) { current, _ in current }, callbackID: callbackID, webView: webView)
        } catch {
            send(["success": false, "code": code(for: error), "error": message(for: error)], callbackID: callbackID, webView: webView)
        }
    }

    private func identity(from webView: WKWebView?) -> (gateway: String, appID: String, origin: String, parameters: [String: String]) {
        let runtime = HTMLAppRuntimeCenter.shared
        guard let context = DrelOAuthManagedContextStore.shared.current,
              context.gatewayIdentity == runtime.gatewayIdentity,
              runtime.trustRegistry.manifest(for: context.appID) != nil else {
            return ("", "", "", [:])
        }
        return (context.gatewayIdentity, context.appID, context.origin, context.parameters)
    }

    private func dictionary(from status: DrelOAuthGrantStatus) throws -> [String: Any] {
        var result: [String: Any] = ["available": status.available, "status": status.status]
        if let grantID = status.grantID { result["grantId"] = grantID }
        if let scope = status.scope { result["scope"] = scope }
        if let expiresIn = status.accessTokenExpiresIn { result["accessTokenExpiresIn"] = expiresIn }
        return result
    }

    private func bodyValue(_ body: DrelOAuthFetchBody) -> Any {
        switch body {
        case .json(let value): return value
        case .text(let value): return value
        case .base64(let value): return value
        }
    }

    private func code(for error: Error) -> String {
        switch error as? DrelOAuthError {
        case .manifestMissing, .manifestInvalid, .invalidRequest: return "invalid_request"
        case .scopeExceeded: return "scope_exceeded"
        case .pairingRequired: return "pairing_required"
        case .consentRequired: return "consent_required"
        case .networkUnavailable: return "network_unavailable"
        case .invalidGrant: return "invalid_grant"
        case .userCancelled: return "user_cancelled"
        case .keyUnavailable, .authorizationRequired: return "authorization_required"
        case nil: return "authorization_failed"
        }
    }

    private func message(for error: Error) -> String {
        (error as? DrelOAuthError).map { code(for: $0) } ?? "authorization_failed"
    }

    private func send(_ result: [String: Any], callbackID: String, webView: WKWebView?) {
        var payload = result
        payload["callbackId"] = callbackID
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let script = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.BarkBridge.receiveResult(\(script));", completionHandler: nil)
    }
}

public enum DrelOAuthBridgeInstaller {
    private static let installedControllersLock = NSLock()
    private static var installedControllers: Set<ObjectIdentifier> = []
    public static let bridgeOverrideJavaScript = """
    (() => {
      if (!window.BarkBridge || window.__drelOAuthBridgeInstalled) return;
      const originalCallNative = window.BarkBridge.callNative.bind(window.BarkBridge);
      window.BarkBridge.callNative = (action, params) => {
        if (!action || !action.startsWith('authorization.')) return originalCallNative(action, params);
        return new Promise((resolve, reject) => {
          const id = 'oauth_' + Date.now() + '_' + Math.random().toString(36).slice(2);
          window.BarkBridge.callbacks[id] = result => {
            if (result.success !== false) resolve(result);
            else reject(new Error(result.error || result.code || 'Authorization failed'));
          };
          window.webkit.messageHandlers.DrelOAuthBridge.postMessage({
            action,
            params: params || {},
            messageId: id,
            callbackId: id
          });
        });
      };
      window.__drelOAuthBridgeInstalled = true;
      window.__drelOAuthBridgeTeardown = () => {
        window.BarkBridge.callNative = originalCallNative;
        delete window.__drelOAuthBridgeInstalled;
        delete window.__drelOAuthBridgeTeardown;
      };
    })();
    """

    @MainActor
    public static func install(
        on webView: WKWebView,
        broker: DrelOAuthBroker,
        context: DrelOAuthManagedContext
    ) {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DrelOAuthBridgeHandler.messageHandlerName)
        controller.add(DrelOAuthBridgeHandler(broker: broker), name: DrelOAuthBridgeHandler.messageHandlerName)
        installedControllersLock.lock()
        let controllerID = ObjectIdentifier(controller)
        let shouldInstallScript = !installedControllers.contains(controllerID)
        if shouldInstallScript { installedControllers.insert(controllerID) }
        installedControllersLock.unlock()
        if shouldInstallScript {
            controller.addUserScript(WKUserScript(
                source: bridgeOverrideJavaScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        webView.evaluateJavaScript(bridgeOverrideJavaScript, completionHandler: nil)
    }

    @MainActor
    public static func prepareLaunch(context: DrelOAuthManagedContext) {
        DrelOAuthManagedContextStore.shared.set(context)
    }

    @MainActor
    public static func attachIfPossible(
        broker: DrelOAuthBroker = DrelOAuthBroker(),
        context: DrelOAuthManagedContext? = nil
    ) {
        if let context { DrelOAuthManagedContextStore.shared.set(context) }
        guard DrelOAuthManagedContextStore.shared.current != nil,
              let browser = WebBrowserManager.shared.getCurrentBrowser(),
              let webView = findWebView(in: browser.view) else { return }
        install(
            on: webView,
            broker: broker,
            context: DrelOAuthManagedContextStore.shared.current!
        )
    }

    @MainActor
    public static func resetBridgeState() {
        DrelOAuthManagedContextStore.shared.set(nil)
        guard let browser = WebBrowserManager.shared.getCurrentBrowser(),
              let webView = findWebView(in: browser.view) else { return }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: DrelOAuthBridgeHandler.messageHandlerName)
        installedControllersLock.lock()
        installedControllers.remove(ObjectIdentifier(controller))
        installedControllersLock.unlock()
        webView.evaluateJavaScript("window.__drelOAuthBridgeTeardown?.()", completionHandler: nil)
    }

    @MainActor
    private static func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        for child in view.subviews {
            if let webView = findWebView(in: child) { return webView }
        }
        return nil
    }
}
