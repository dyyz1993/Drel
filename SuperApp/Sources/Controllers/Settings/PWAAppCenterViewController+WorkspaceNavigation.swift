import SwiftUI
import UIKit
import WebBridgeKit

extension PWAAppCenterViewController {
    func showAppDiagnostics() {
        let diagnostics = UIHostingController(rootView: OfflineAppHealthView())
        diagnostics.navigationItem.title = L10n.tr("home.apps.unavailable.diagnostics")
        diagnostics.view.backgroundColor = ThemeTokens.Color.background
        navigationController?.pushViewController(diagnostics, animated: true)
    }

    func showAddAppFromPushHint() {
        let alert = UIAlertController(
            title: L10n.tr("home.apps.empty.add_from_push"),
            message: L10n.tr("home.apps.empty.add_from_push_hint"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.tr("common.ok"), style: .default))
        present(alert, animated: true)
    }

    func showAppRegistration() {
        let registration = AppRegistrationViewController { [weak self] appID in
            self?.showActivatedAppInCatalog(appID: appID)
        }
        navigationController?.pushViewController(registration, animated: true)
    }

    func showActivatedAppInCatalog(appID: String) {
        navigationController?.pushViewController(
            PWAAppCatalogViewController(initiallySelectedAppID: appID),
            animated: true
        )
        WebBridgeLogger.shared.info("Registered app opened in catalog: \(appID)")
    }

    func appInitial(name: String, appID: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmedName.first { return String(first).uppercased() }
        let appComponent = appID.split(separator: ".").last.map(String.init) ?? appID
        if let first = appComponent.first { return String(first).uppercased() }
        return "D"
    }

    func appTint(for manifest: HTMLAppManifest) -> UIColor {
        let value = manifest.appID.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) % 4
        }
        switch value {
        case 0: return ThemeTokens.Color.primary
        case 1: return ThemeTokens.Color.info
        case 2: return ThemeTokens.Color.warning
        default: return ThemeTokens.Color.accent
        }
    }
}
