//
//  DrelAppOpenFallback.swift
//  SuperApp
//

import Foundation
import SwiftUI
import UIKit
import WebBridgeKit

enum DrelAppOpenFailure: Error, Equatable {
    case invalidLink
    case catalogRejected(appID: String, untrustedManifests: [HTMLAppManifest])
    case untrustedRoute(appID: String)
    case resolution(appID: String, message: String)
}

enum DrelAppOpenFallback {
    enum FallbackDecision: Equatable {
        case openInBrowser(URL, appName: String)
        case cannotOpen(reason: DrelAppOpenFailure)
    }

    static func decide(
        appID: String?,
        route: String?,
        untrustedManifests: [HTMLAppManifest],
        payload: PushPayload?
    ) -> FallbackDecision {
        let requestedAppID = appID ?? payload?.appid
        let manifest = untrustedManifests.first { $0.appID == requestedAppID }
        let appName = payload?.title ?? manifest?.name ?? requestedAppID ?? "应用"

        if let url = trustedHTTPSURL(from: payload?.url) {
            return .openInBrowser(url, appName: appName)
        }
        if let manifest, let url = trustedHTTPSURL(from: manifest.startURL)
            ?? manifest.allowedOrigins.lazy.compactMap({ trustedHTTPSURL(from: $0) }).first {
            return .openInBrowser(url, appName: appName)
        }
        if let url = deriveStartURL(fromAppID: requestedAppID) {
            return .openInBrowser(url, appName: appName)
        }
        return .cannotOpen(reason: .untrustedRoute(appID: requestedAppID ?? ""))
    }

    static func decide(failure: DrelAppOpenFailure, payload: PushPayload?) -> FallbackDecision {
        switch failure {
        case .invalidLink:
            return .cannotOpen(reason: failure)
        case .catalogRejected(let appID, let manifests):
            return decide(appID: appID, route: payload?.route, untrustedManifests: manifests, payload: payload)
        case .untrustedRoute(let appID):
            return decide(appID: appID, route: payload?.route, untrustedManifests: [], payload: payload)
        case .resolution(let appID, _):
            return decide(appID: appID, route: payload?.route, untrustedManifests: [], payload: payload)
        }
    }

    static func decide(
        failure: DrelAppOpenFailure,
        message: MessagePayload,
        appID: String,
        route: String?
    ) -> FallbackDecision {
        decide(failure: failure, payload: pushPayload(from: message, appID: appID, route: route))
    }

    static func pushPayload(from message: MessagePayload, appID: String, route: String?) -> PushPayload {
        var userInfo = message.userInfo ?? [:]
        userInfo["appId"] = userInfo["appId"] ?? appID
        userInfo["route"] = route
        userInfo["title"] = userInfo["title"] ?? message.title
        if let targetURL = message.targetURL { userInfo["url"] = userInfo["url"] ?? targetURL }
        if let targetMode = message.targetMode { userInfo["mode"] = userInfo["mode"] ?? targetMode }
        return PushPayload(userInfo: userInfo)
    }

    static func deriveStartURL(fromAppID appID: String?) -> URL? {
        guard let appID, appID.lowercased().hasPrefix("app.") else { return nil }
        let host = String(appID.dropFirst("app.".count)).lowercased()
        guard host.split(separator: ".").count >= 2,
              !host.contains("dev.drel"),
              !host.contains("com.webbridgekit"),
              let url = URL(string: "https://\(host)/"),
              url.scheme?.lowercased() == "https",
              url.host?.caseInsensitiveCompare(host) == .orderedSame,
              isPublicHost(host) else { return nil }
        return url
    }

    /// Shared with the "add app by address" screen so typed input gets the
    /// same userinfo and private-host checks as a push-driven fallback.
    static func trustedHTTPSURLForRegistration(from rawValue: String) -> URL? {
        trustedHTTPSURL(from: rawValue)
    }

    private static func trustedHTTPSURL(from rawValue: String?) -> URL? {
        guard let rawValue, let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              // `https://real.example@evil.com` reads as "real.example" to a
              // user but navigates to evil.com; never open a URL with userinfo.
              url.user == nil, url.password == nil,
              isPublicHost(url.host ?? "") else { return nil }
        return url
    }

    /// A fallback URL is opened without any manifest, so it must not be able
    /// to reach the device's own network: loopback, link-local (including
    /// cloud metadata 169.254.169.254), RFC 1918 ranges and `.local` names
    /// are all rejected. Only a publicly resolvable name may be derived.
    static func isPublicHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if lowered.isEmpty || lowered.hasSuffix(".local") || lowered.hasSuffix(".localhost")
            || lowered == "localhost" || lowered.contains("metadata") || lowered.contains("localhost") {
            return false
        }
        // IPv4 literal: reject private, loopback, link-local and reserved ranges.
        let parts = lowered.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, lowered.split(separator: ".").count == 4 {
            let (a, b) = (parts[0], parts[1])
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            return true
        }
        // Anything that parses as an IPv6 literal (contains ":") is not a name
        // we ever derive or accept from an untrusted source.
        if lowered.contains(":") { return false }
        // Bare IPv4-looking strings that failed to parse (e.g. "999.1.1.1") and
        // single-label names are not public hosts either.
        if lowered.split(separator: ".").count < 2 { return false }
        return true
    }

    static func presentCannotOpen(_ failure: DrelAppOpenFailure, from viewController: UIViewController?) {
        DispatchQueue.main.async {
            var presenter = viewController ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first
            while let presented = presenter?.presentedViewController { presenter = presented }
            let alert = UIAlertController(
                title: L10n.tr("app.open.fallback.failed_title", appName(for: failure)),
                message: reason(for: failure),
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(
                title: L10n.tr("app.open.fallback.diagnostics"),
                style: .default
            ) { _ in
                let diagnostics = UIHostingController(rootView: OfflineAppHealthView())
                diagnostics.title = L10n.tr("app.open.fallback.diagnostics")
                presenter?.present(UINavigationController(rootViewController: diagnostics), animated: true)
            })
            alert.addAction(UIAlertAction(title: L10n.tr("common.cancel"), style: .cancel))
            presenter?.present(alert, animated: true)
        }
    }

    static func presentBrowserFallback(
        _ decision: FallbackDecision,
        from viewController: UIViewController?
    ) {
        guard case .openInBrowser(let url, let appName) = decision else {
            if case .cannotOpen(let reason) = decision {
                presentCannotOpen(reason, from: viewController)
            }
            return
        }
        let params = DrelMessageOpenPolicy.browserParams(
            for: url,
            mode: .normal,
            payload: nil,
            useManifestLoader: false,
            preferCachedContent: false
        )
        WebBrowserManager.shared.openBrowser(url: url, params: params, from: viewController) { _ in
            BrowserFallbackNotice.present(appName: appName, source: viewController)
        }
    }

    private static func appName(for failure: DrelAppOpenFailure) -> String {
        switch failure {
        case .invalidLink: return "应用"
        case .catalogRejected(let appID, _), .untrustedRoute(let appID): return appID
        case .resolution(let appID, _): return appID
        }
    }

    private static func reason(for failure: DrelAppOpenFailure) -> String {
        switch failure {
        case .invalidLink:
            return L10n.tr("app.open.fallback.invalid_link")
        case .catalogRejected, .untrustedRoute:
            return L10n.tr("app.open.fallback.untrusted")
        case .resolution(_, let message):
            return L10n.tr("app.open.fallback.resolution", message)
        }
    }
}

private final class BrowserFallbackNotice {
    private static var activeView: UIView?

    static func present(appName: String, source: UIViewController?) {
        DispatchQueue.main.async {
            var presenter = source ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first
            while let presented = presenter?.presentedViewController { presenter = presented }
            guard let container = presenter?.view else { return }
            activeView?.removeFromSuperview()

            let notice = makeNotice(appName: appName)
            container.addSubview(notice)
            notice.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                notice.topAnchor.constraint(
                    equalTo: container.safeAreaLayoutGuide.topAnchor,
                    constant: 10
                ),
                notice.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                notice.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                notice.heightAnchor.constraint(equalToConstant: 46)
            ])
            activeView = notice
            notice.alpha = 0
            UIView.animate(withDuration: 0.22) { notice.alpha = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                dismiss(notice)
            }
        }
    }

    private static func makeNotice(appName: String) -> UIView {
        let notice = UIView()
        notice.backgroundColor = ThemeTokens.Color.background.withAlphaComponent(0.97)
        notice.layer.cornerRadius = 14
        notice.layer.shadowColor = UIColor.black.cgColor
        notice.layer.shadowOpacity = 0.14
        notice.layer.shadowRadius = 10
        notice.layer.shadowOffset = CGSize(width: 0, height: 4)

        let label = UILabel()
        label.text = L10n.tr("app.open.fallback.browser_notice", appName)
        label.font = ThemeTokens.Typography.footnote
        label.textColor = ThemeTokens.Color.text
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let addButton = UIButton(type: .system)
        addButton.setTitle(L10n.tr("app.open.fallback.add_app"), for: .normal)
        addButton.titleLabel?.font = .systemFont(
            ofSize: ThemeTokens.Typography.footnote.pointSize,
            weight: .semibold
        )
        addButton.addTarget(BrowserFallbackNotice.self, action: #selector(addTapped), for: .touchUpInside)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle(L10n.tr("common.close"), for: .normal)
        closeButton.titleLabel?.font = ThemeTokens.Typography.footnote

        notice.addSubview(label)
        notice.addSubview(addButton)
        notice.addSubview(closeButton)
        label.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: notice.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: notice.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: notice.centerYAnchor),
            addButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            addButton.trailingAnchor.constraint(equalTo: notice.trailingAnchor, constant: -14),
            addButton.centerYAnchor.constraint(equalTo: notice.centerYAnchor)
        ])

        closeButton.addAction(UIAction { _ in dismiss(notice) }, for: .touchUpInside)
        return notice
    }

    @objc private static func addTapped() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first as? UITabBarController,
            let nav = root.viewControllers?.first as? UINavigationController else {
            return
        }
        root.dismiss(animated: true)
        root.selectedIndex = 0
        nav.popToRootViewController(animated: false)
    }

    private static func dismiss(_ notice: UIView) {
        guard notice.superview != nil else { return }
        UIView.animate(
            withDuration: 0.22,
            animations: { notice.alpha = 0 },
            completion: { _ in
                notice.removeFromSuperview()
                if activeView === notice { activeView = nil }
            }
        )
    }
}
