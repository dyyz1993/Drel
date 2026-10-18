import WebBridgeKit

enum DrelGatewayConfiguration {
    static let official = HTMLAppGatewayConfiguration(
        id: "drel-gateway",
        name: "Drel 官方服务",
        baseURL: "https://api.drel.app",
        healthPath: "/health",
        manifestPath: "/api/v1/html-apps",
        publicKeyID: "gw-2026-09-15",
        publicKey: "M3FVnjzVa8bjFQ-VtDov_mvYrik6c-DGSaRm-wdcLzY"
    )
}
