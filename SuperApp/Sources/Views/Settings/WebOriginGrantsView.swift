// This is a reusable/Debug bridge-management screen. It must not ship in the
// Drel Store product, where remote pages have no native Bridge surface.
#if !DREL_CONTAINER_ONLY
import SwiftUI
import WebBridgeKit

/// 网页（origin）维度的授权总览。
///
/// 权限中心按「应用」维度展示；本页按「网页域名」聚合授权账本，
/// 回答「哪些网站被授予了什么原生能力、什么时候授的、如何撤销」。
struct WebOriginGrantsView: View {

    @State private var grantsByOrigin: [(origin: String, grants: [HTMLAppPermissionGrant])] = []

    var body: some View {
        Group {
            if grantsByOrigin.isEmpty {
                VStack(spacing: ThemeTokens.Spacing.md) {
                    Image(uiImage: LucideIcon.globe.templateImage(pointSize: 44, weight: .light) ?? UIImage())
                        .foregroundStyle(Color(ThemeTokens.Color.textTertiary))
                    Text("暂无网页授权")
                        .font(Font.app(ThemeTokens.Typography.body))
                        .foregroundStyle(Color(ThemeTokens.Color.textSecondary))
                    Text("网页通过 Bridge 调用受保护能力并经你确认后，会记录在这里")
                        .font(Font.app(ThemeTokens.Typography.caption))
                        .foregroundStyle(Color(ThemeTokens.Color.textTertiary))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(ThemeTokens.Spacing.xl)
            } else {
                List {
                    ForEach(grantsByOrigin, id: \.origin) { group in
                        Section {
                            ForEach(Array(group.grants.enumerated()), id: \.offset) { index, grant in
                                GrantRow(grant: grant) {
                                    requestRevoke(grant)
                                }
                            }
                        } header: {
                            Text(group.origin)
                                .font(Font.app(ThemeTokens.Typography.caption))
                                .foregroundStyle(Color(ThemeTokens.Color.textSecondary))
                        }
                    }

                    Text("按网页域名维度记录。撤销后，该网页再次使用对应能力时会重新请求授权。")
                        .font(Font.app(ThemeTokens.Typography.caption))
                        .foregroundStyle(Color(ThemeTokens.Color.textTertiary))
                        .listRowBackground(Color.clear)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("网页授权管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert("撤销这项授权？", isPresented: $showingRevokeConfirm) {
            Button("撤销", role: .destructive) { confirmRevoke() }
            Button("取消", role: .cancel) { pendingRevoke = nil }
        } message: {
            Text("撤销后，该网页再次使用对应能力时会重新请求授权。")
        }
    }

    @State private var showingRevokeConfirm = false
    @State private var pendingRevoke: HTMLAppPermissionGrant?

    private func reload() {
        // 只列持久授权：「仅这一次」是一次性事实，不该出现在授权管理里
        // （2026-10-22 与权限中心口径对齐）。注意账本本身不持久化 .once，
        // 这里主要过滤掉会话级授权中的瞬时记录。
        let persistent = HTMLAppPermissionLedger.shared.allGrants().filter { $0.scope != .once }
        let grouped = Dictionary(grouping: persistent) { $0.origin }
        grantsByOrigin = grouped
            .map { (origin: $0.key, grants: $0.value.sorted { $0.grantedAt > $1.grantedAt }) }
            .sorted { $0.origin < $1.origin }
    }

    /// 撤销必须二次确认（2026-10-22 用户实测：点卡片整行就消失了）。
    /// 直接执行会让误触瞬间丢掉授权，且行本身没有可观察的撤销入口。
    private func requestRevoke(_ grant: HTMLAppPermissionGrant) {
        pendingRevoke = grant
        showingRevokeConfirm = true
    }

    private func confirmRevoke() {
        guard let grant = pendingRevoke else { return }
        pendingRevoke = nil
        HTMLAppPermissionLedger.shared.revoke(
            appID: grant.appID,
            origin: grant.origin,
            capability: grant.capability
        )
        reload()
    }
}

private struct GrantRow: View {

    let grant: HTMLAppPermissionGrant
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: ThemeTokens.Spacing.md) {
            Image(uiImage: icon.templateImage(pointSize: 20, weight: .medium) ?? UIImage())
                .foregroundStyle(Color(ThemeTokens.Color.primary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.sm)
                        .fill(Color(ThemeTokens.Color.primarySoft))
                )

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                Text(grant.capability.displayName)
                    .font(Font.app(ThemeTokens.Typography.rowTitle))
                    .foregroundStyle(Color(ThemeTokens.Color.text))

                // 时间一行、appID 一行——合并在单行时 appID（local.https://…）
                // 会把授权时间挤出截断（2026-08-23 用户反馈时间看不到）
                Text("\(scopeTitle) · \(grant.grantedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Font.app(ThemeTokens.Typography.caption2))
                    .foregroundStyle(Color(ThemeTokens.Color.textSecondary))
                Text(grant.appID)
                    .font(Font.app(ThemeTokens.Typography.caption2))
                    .foregroundStyle(Color(ThemeTokens.Color.textTertiary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            // 热区收紧到按钮自身：默认 List 行的 Button 可点区域会横向铺满整行，
            // 用户点卡片空白处也会触发撤销（2026-10-22 用户实测）
            Button("撤销", action: onRevoke)
                .font(Font.app(ThemeTokens.Typography.buttonMedium))
                .foregroundStyle(Color(ThemeTokens.Color.error))
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(minWidth: 44, minHeight: 34)
        }
        .padding(.vertical, ThemeTokens.Spacing.xs)
    }

    private var scopeTitle: String {
        switch grant.scope {
        case .once: return "仅这一次"
        case .appSession: return "本次使用期间"
        case .always: return "始终允许"
        }
    }

    private var icon: LucideIcon {
        switch grant.capability {
        case .location: return .pin
        case .camera: return .camera
        case .microphone: return .mic
        case .photoLibrary: return .image
        case .notification: return .bell
        case .clipboard: return .clipboard
        case .scan: return .qrCode
        case .share: return .share
        default: return .shield
        }
    }
}
#endif
