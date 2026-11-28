import UIKit

struct PWAAppCatalogItem: Identifiable {
    struct Capability: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    let id: String
    let name: String
    let iconURL: URL?
    let iconCacheKey: String
    let fallbackInitial: String
    let tint: UIColor
    let version: String
    let sourceHost: String
    let sourceOrigins: [String]
    let signatureAlgorithm: String
    let signatureKeyID: String
    let startURL: String
    let routes: [String]
    let offlineSummary: String
    let capabilities: [Capability]
    let isActivated: Bool
}

@MainActor
final class PWAAppCatalogViewModel: ObservableObject {
    @Published var apps: [PWAAppCatalogItem]
    @Published var gatewayName: String

    init(apps: [PWAAppCatalogItem], gatewayName: String) {
        self.apps = apps
        self.gatewayName = gatewayName
    }
}
