import SwiftUI
import WebBridgeKit

struct PWAHomeAppsEmptyStateView: View {
    let appState: PWAHomeViewModel.AppState
    let gatewayFailure: (title: String, message: String)?
    let onManageApps: () -> Void
    let onRetryApps: () -> Void
    let onOpenAppDiagnostics: () -> Void
    let onAddAppFromPush: () -> Void
    let onEnterAppAddress: () -> Void

    var body: some View {
        switch appState {
        case .loading:
            emptyAppsLink
        case .ready:
            VStack(spacing: ThemeTokens.Spacing.md) {
                emptyAppsHeader
                HStack(spacing: ThemeTokens.Spacing.sm) {
                    emptyAppsButton(
                        title: L10n.tr("home.apps.empty.add_from_push"),
                        icon: .bell,
                        identifier: "pwaHome.addAppFromPush",
                        action: onAddAppFromPush
                    )
                    emptyAppsButton(
                        title: L10n.tr("home.apps.empty.enter_address"),
                        icon: .link,
                        identifier: "pwaHome.enterAppAddress",
                        action: onEnterAppAddress
                    )
                }
            }
        case .unavailable:
            VStack(spacing: ThemeTokens.Spacing.md) {
                emptyAppsHeader
                HStack(spacing: ThemeTokens.Spacing.sm) {
                    emptyAppsButton(
                        title: L10n.tr("home.apps.unavailable.retry"),
                        icon: .refresh,
                        identifier: "pwaHome.retryApps",
                        action: onRetryApps
                    )
                    emptyAppsButton(
                        title: L10n.tr("home.apps.unavailable.diagnostics"),
                        icon: .info,
                        identifier: "pwaHome.openAppDiagnostics",
                        action: onOpenAppDiagnostics
                    )
                }
            }
        }
    }

    private var emptyAppsLink: some View {
        Button(action: onManageApps) {
            emptyAppsHeader
                .overlay(alignment: .trailing) {
                    Image(uiImage: LucideIcon.chevronRight.templateImage(pointSize: ThemeTokens.Icons.Sizes.chevron) ?? UIImage())
                        .renderingMode(.template)
                        .foregroundColor(Color.appTextTertiary)
                        .padding(.trailing, ThemeTokens.Spacing.lg)
                }
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier("pwaHome.emptyApps")
    }

    private var emptyAppsHeader: some View {
        HStack(spacing: ThemeTokens.Spacing.md) {
            Image(uiImage: LucideIcon.plus.templateImage(pointSize: ThemeTokens.Icons.Sizes.md) ?? UIImage())
                .renderingMode(.template)
                .foregroundColor(Color.appPrimary)
                .frame(width: 40, height: 40)
                .background(Color(ThemeTokens.Color.primarySoft))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.md))

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                Text(emptyAppsTitle)
                    .font(.system(size: ThemeTokens.Typography.rowTitle.pointSize, weight: .medium))
                    .foregroundColor(Color.appText)
                Text(emptyAppsSubtitle)
                    .font(Font.app(ThemeTokens.Typography.metadata))
                    .foregroundColor(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(ThemeTokens.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
    }

    private func emptyAppsButton(
        title: String,
        icon: LucideIcon,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ThemeTokens.Spacing.xs) {
                Image(uiImage: icon.templateImage(pointSize: ThemeTokens.Icons.Sizes.sm) ?? UIImage())
                    .renderingMode(.template)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: ThemeTokens.Typography.buttonMedium.pointSize, weight: .semibold))
            .foregroundColor(Color.appPrimary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color(ThemeTokens.Color.primarySoft))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.md))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    private var emptyAppsTitle: String {
        switch appState {
        case .loading: return "正在连接应用服务"
        case .ready: return "还没有添加应用"
        case .unavailable: return "暂时没有可用的应用"
        }
    }

    private var emptyAppsSubtitle: String {
        switch appState {
        case .loading: return "正在校验受签名的应用清单"
        case .ready: return "连接官方或自部署应用服务"
        case .unavailable: return gatewayFailure?.message ?? L10n.tr("home.apps.failure.generic")
        }
    }
}
