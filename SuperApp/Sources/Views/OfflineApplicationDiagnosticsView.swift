import SwiftUI
import WebBridgeKit

struct OfflineAppHealthView: View {
    @State private var attempts: [DrelOfflineDiagnostics.Attempt] = []
    @State private var selectedAppID: String?
    @State private var statusMessage = "诊断只保存在本机"

    private var appIDs: [String] {
        Array(Set(attempts.map(\.appID))).sorted()
    }

    private var visibleAttempts: [DrelOfflineDiagnostics.Attempt] {
        guard let selectedAppID else { return attempts }
        return attempts.filter { $0.appID == selectedAppID }
    }

    var body: some View {
        List {
            Section {
                Picker("应用", selection: Binding(
                    get: { selectedAppID ?? "" },
                    set: { selectedAppID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("全部应用").tag("")
                    ForEach(appIDs, id: \.self) { appID in
                        Text(appID).tag(appID)
                    }
                }
                Button {
                    UIPasteboard.general.string = DrelOfflineDiagnostics.shared.copyReport(appID: selectedAppID)
                    statusMessage = "诊断报告已复制"
                } label: {
                    HStack {
                        Image(uiImage: LucideIcon.copy.templateImage() ?? UIImage())
                        Text("复制当前诊断")
                    }
                }
                .accessibilityIdentifier("offlineDiagnostics.copy")
                Button(role: .destructive) {
                    DrelOfflineDiagnostics.shared.clear()
                    reload()
                    statusMessage = "本机诊断已清除"
                } label: {
                    HStack {
                        Image(uiImage: LucideIcon.trash.templateImage() ?? UIImage())
                        Text("清除本机诊断")
                    }
                }
                .accessibilityIdentifier("offlineDiagnostics.clear")
                Text(statusMessage)
                    .font(Font.app(ThemeTokens.Typography.caption1))
                    .foregroundColor(Color.appTextSecondary)
                    .accessibilityIdentifier("offlineDiagnostics.status")
            }

            Section {
                if visibleAttempts.isEmpty {
                    Text("暂无打开记录")
                        .foregroundColor(Color.appTextSecondary)
                        .accessibilityIdentifier("offlineDiagnostics.empty")
                } else {
                    ForEach(visibleAttempts) { attempt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(attempt.appID)
                                .font(Font.app(ThemeTokens.Typography.body))
                                .foregroundColor(Color.appText)
                            Text("Drel \(attempt.hostVersion)+\(attempt.hostBuild) · 包 \(attempt.packageVersion ?? "无") · \(attempt.currentLoadSource.displayName)")
                                .font(Font.app(ThemeTokens.Typography.caption1))
                                .foregroundColor(Color.appTextSecondary)
                            if let phase = attempt.failurePhase {
                                Text("失败阶段：\(phase.displayName)")
                                    .font(Font.app(ThemeTokens.Typography.caption1))
                                    .foregroundColor(Color.appError)
                            }
                            ForEach(Array(attempt.events.suffix(8).enumerated()), id: \.offset) { _, event in
                                Text("\(event.timestamp, style: .time) · \(event.phase.displayName) · \(event.status.rawValue) · \(event.outcome ?? "")")
                                    .font(Font.app(ThemeTokens.Typography.caption2))
                                    .foregroundColor(Color.appTextSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("offlineDiagnostics.attempt.\(attempt.id)")
                    }
                }
            } header: {
                Text("最近 \(visibleAttempts.count) 次打开")
            }
        }
        .appListStyle()
        .listStyle(.insetGrouped)
        .navigationTitle("离线应用诊断")
        .accessibilityIdentifier("offlineDiagnostics.root")
        .onAppear {
            reload()
        }
    }

    private func reload() {
        attempts = DrelOfflineDiagnostics.shared.attempts()
        if let selectedAppID, !appIDs.contains(selectedAppID) {
            self.selectedAppID = nil
        }
    }
}

private extension DrelOfflineDiagnostics.Attempt.LoadSource {
    var displayName: String {
        switch self {
        case .offlinePackage: return "离线包"
        case .online: return "在线页面"
        case .unknown: return "来源未知"
        }
    }
}

private extension DrelOfflineDiagnostics.Attempt.Phase {
    var displayName: String {
        switch self {
        case .launch: return "启动"
        case .package: return "包定位"
        case .navigation: return "WebKit 导航"
        case .page: return "页面可见"
        case .fallback: return "在线兜底"
        case .api: return "应用 API"
        }
    }
}
