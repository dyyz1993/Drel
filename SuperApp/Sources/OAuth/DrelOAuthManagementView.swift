import SwiftUI
import WebBridgeKit

public struct DrelOAuthManagementView: View {
    @State private var rows: [DrelOAuthValidatedManifest] = []
    @State private var statusText = "检查授权中…"
    @State private var isResetting = false
    private let broker: DrelOAuthBroker

    public init(broker: DrelOAuthBroker = DrelOAuthBroker()) {
        self.broker = broker
    }

    public var body: some View {
        List {
            Section("应用授权") {
                if rows.isEmpty {
                    Text("当前网关没有提供 OAuth 授权应用。")
                        .font(.footnote)
                        .foregroundColor(Color.secondary)
                } else {
                    ForEach(rows, id: \.appID) { row in
                        authorizationRow(row)
                    }
                }
            }

            Section {
                Button {
                    clearLocalAuthorizations()
                } label: {
                    if isResetting {
                        ProgressView()
                    } else {
                        Text("清除本地授权记录")
                            .foregroundColor(.red)
                    }
                }
                .disabled(isResetting)
            } footer: {
                Text(statusText)
            }
        }
        .navigationTitle("应用授权")
        .onAppear(perform: reload)
    }

    private func authorizationRow(_ manifest: DrelOAuthValidatedManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manifest.appID)
                .font(.headline)
            Text(manifest.resourceOrigin)
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(manifest.scopes.map(\.name).sorted().joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
            Button("撤销授权") {
                revoke(manifest)
            }
        }
    }

    private func reload() {
        rows = HTMLAppRuntimeCenter.shared.trustRegistry.registeredManifests().compactMap {
            try? DrelOAuthTrustedManifestReader.validatedManifest(appID: $0.appID, trustRegistry: HTMLAppRuntimeCenter.shared.trustRegistry)
        }
        statusText = rows.isEmpty ? "没有可用授权" : "已发现 \(rows.count) 个授权应用"
    }

    private func revoke(_ manifest: DrelOAuthValidatedManifest) {
        Task { @MainActor in
            do {
                try await broker.revoke(
                    gatewayIdentity: HTMLAppRuntimeCenter.shared.gatewayIdentity,
                    appID: manifest.appID,
                    documentOrigin: manifest.startURL
                )
                statusText = "已撤销 \(manifest.appID)"
            } catch {
                statusText = "本地撤销完成；服务器撤销将在下次在线时重试"
            }
            reload()
        }
    }

    private func clearLocalAuthorizations() {
        isResetting = true
        Task { @MainActor in
            defer { isResetting = false }
            do {
                try await broker.revokeAll(appIDs: rows.map(\.appID))
                statusText = "本地授权记录已清除"
            } catch {
                statusText = "清除失败：Keychain 访问被拒绝"
            }
            reload()
        }
    }
}
