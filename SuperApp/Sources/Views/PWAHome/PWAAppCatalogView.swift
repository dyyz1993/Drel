import SwiftUI
import UIKit
import WebBridgeKit

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

struct PWAAppCatalogView: View {
    @ObservedObject var viewModel: PWAAppCatalogViewModel
    let onOpen: (PWAAppCatalogItem) -> Void
    let onAddToHome: (PWAAppCatalogItem) -> Void

    @State private var selectedApp: PWAAppCatalogItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ThemeTokens.Spacing.md) {
                sourceHeader

                if viewModel.apps.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.apps) { app in
                        Button {
                            selectedApp = app
                        } label: {
                            appRow(app)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityIdentifier("pwaCatalog.app.\(app.id)")
                    }
                }
            }
            .padding(ThemeTokens.Spacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle("全部应用")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedApp) { app in
            PWAAppCatalogDetailView(
                app: app,
                gatewayName: viewModel.gatewayName,
                onOpen: {
                    selectedApp = nil
                    onOpen(app)
                },
                onAddToHome: {
                    selectedApp = nil
                    onAddToHome(app)
                }
            )
        }
    }

    private var sourceHeader: some View {
        HStack(alignment: .top, spacing: ThemeTokens.Spacing.md) {
            Image(uiImage: LucideIcon.shield.templateImage(
                pointSize: ThemeTokens.Icons.Sizes.md
            ) ?? UIImage())
                .renderingMode(.template)
                .foregroundColor(Color.appSuccess)
                .frame(width: 40, height: 40)
                .background(Color.appSuccess.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.sm))

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                Text(viewModel.gatewayName)
                    .font(.system(size: ThemeTokens.Typography.rowTitle.pointSize, weight: .semibold))
                    .foregroundColor(Color.appText)
                Text("只列出通过当前应用服务签名校验的应用。打开不会自动加入首页。")
                    .font(Font.app(ThemeTokens.Typography.metadata))
                    .foregroundColor(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ThemeTokens.Spacing.md)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: ThemeTokens.Spacing.sm) {
            Text("没有可浏览的签名应用")
                .font(.system(size: ThemeTokens.Typography.rowTitle.pointSize, weight: .semibold))
                .foregroundColor(Color.appText)
            Text("刷新应用服务后，签名清单会出现在这里。")
                .font(Font.app(ThemeTokens.Typography.metadata))
                .foregroundColor(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(ThemeTokens.Spacing.xl)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card))
    }

    private func appRow(_ app: PWAAppCatalogItem) -> some View {
        HStack(spacing: ThemeTokens.Spacing.md) {
            PWAAppIconView(
                iconURL: app.iconURL,
                cacheKey: app.iconCacheKey,
                fallbackInitial: app.fallbackInitial,
                tint: app.tint
            )
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: ThemeTokens.Spacing.xs) {
                    Text(app.name)
                        .font(.system(size: ThemeTokens.Typography.rowTitle.pointSize, weight: .semibold))
                        .foregroundColor(Color.appText)
                        .lineLimit(1)

                    if app.isActivated {
                        Text("首页")
                            .font(Font.app(ThemeTokens.Typography.caption2))
                            .foregroundColor(Color.appSuccess)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.appSuccess.opacity(0.12), in: Capsule())
                    }
                }

                Text("\(app.sourceHost) · 版本 \(app.version)")
                    .font(Font.app(ThemeTokens.Typography.metadata))
                    .foregroundColor(Color.appTextSecondary)
                    .lineLimit(1)

                Text(capabilitySummary(app))
                    .font(Font.app(ThemeTokens.Typography.caption2))
                    .foregroundColor(Color.appTextTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: ThemeTokens.Spacing.sm)

            Image(uiImage: LucideIcon.chevronRight.templateImage(
                pointSize: ThemeTokens.Icons.Sizes.chevron
            ) ?? UIImage())
                .renderingMode(.template)
                .foregroundColor(Color.appTextTertiary)
        }
        .padding(ThemeTokens.Spacing.md)
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card)
                .stroke(Color.appSeparator, lineWidth: 1)
        )
    }

    private func capabilitySummary(_ app: PWAAppCatalogItem) -> String {
        guard !app.capabilities.isEmpty else { return "未声明原生能力" }
        return app.capabilities.prefix(3).map(\.title).joined(separator: " · ")
    }
}

private struct PWAAppCatalogDetailView: View {
    let app: PWAAppCatalogItem
    let gatewayName: String
    let onOpen: () -> Void
    let onAddToHome: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.lg) {
                    identityHeader
                    sourceSection
                    capabilitySection
                    routeSection
                    actionButtons
                }
                .padding(ThemeTokens.Spacing.lg)
            }
            .background(Color.appBackground)
            .navigationTitle("应用详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var identityHeader: some View {
        HStack(spacing: ThemeTokens.Spacing.md) {
            PWAAppIconView(
                iconURL: app.iconURL,
                cacheKey: app.iconCacheKey,
                fallbackInitial: app.fallbackInitial,
                tint: app.tint
            )
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                Text(app.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color.appText)
                Text(app.isActivated ? "已添加到首页" : "尚未添加到首页")
                    .font(Font.app(ThemeTokens.Typography.metadata))
                    .foregroundColor(app.isActivated ? Color.appSuccess : Color.appTextSecondary)
                Text("版本 \(app.version) · \(app.offlineSummary)")
                    .font(Font.app(ThemeTokens.Typography.caption2))
                    .foregroundColor(Color.appTextTertiary)
            }
        }
    }

    private var sourceSection: some View {
        detailSection(title: "来源与签名") {
            detailRow("应用服务", gatewayName)
            detailRow("来源域名", app.sourceOrigins.joined(separator: "\n"))
            detailRow("App ID", app.id)
            detailRow("签名", "\(app.signatureAlgorithm) · \(app.signatureKeyID)")
            detailRow("入口", app.startURL)
        }
    }

    private var capabilitySection: some View {
        detailSection(title: "能力声明") {
            if app.capabilities.isEmpty {
                Text("此应用未声明 Bridge 原生能力。")
                    .font(Font.app(ThemeTokens.Typography.body))
                    .foregroundColor(Color.appTextSecondary)
            } else {
                ForEach(app.capabilities) { capability in
                    VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                        Text(capability.title)
                            .font(.system(size: ThemeTokens.Typography.rowTitle.pointSize, weight: .medium))
                            .foregroundColor(Color.appText)
                        Text(capability.detail)
                            .font(Font.app(ThemeTokens.Typography.metadata))
                            .foregroundColor(Color.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if capability.id != app.capabilities.last?.id {
                        Divider().overlay(Color.appSeparator)
                    }
                }
            }
        }
    }

    private var routeSection: some View {
        detailSection(title: "允许的路由") {
            Text(app.routes.joined(separator: "\n"))
                .font(Font.app(ThemeTokens.Typography.metadata))
                .foregroundColor(Color.appTextSecondary)
                .textSelection(.enabled)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: ThemeTokens.Spacing.sm) {
            Button(action: onOpen) {
                Text("打开应用")
                    .font(.system(size: ThemeTokens.Typography.buttonMedium.pointSize, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(.white)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.md))
            }
            .accessibilityIdentifier("pwaCatalog.open")

            Button(action: onAddToHome) {
                Text(app.isActivated ? "已在首页" : "添加到首页")
                    .font(.system(size: ThemeTokens.Typography.buttonMedium.pointSize, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(app.isActivated ? Color.appTextTertiary : Color.appPrimary)
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.md)
                            .stroke(Color.appSeparator, lineWidth: 1)
                    )
            }
            .disabled(app.isActivated)
            .accessibilityIdentifier("pwaCatalog.addToHome")
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.md) {
            Text(title)
                .font(.system(size: ThemeTokens.Typography.sectionTitle.pointSize, weight: .semibold))
                .foregroundColor(Color.appText)
            VStack(alignment: .leading, spacing: ThemeTokens.Spacing.md) {
                content()
            }
            .padding(ThemeTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.card)
                    .stroke(Color.appSeparator, lineWidth: 1)
            )
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.app(ThemeTokens.Typography.caption2))
                .foregroundColor(Color.appTextTertiary)
            Text(value)
                .font(Font.app(ThemeTokens.Typography.metadata))
                .foregroundColor(Color.appTextSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class PWAAppCatalogViewController: UIViewController {
    private let runtime = HTMLAppRuntimeCenter.shared
    private let gatewayRegistry = HTMLAppGatewayRegistry(
        officialGateway: DrelGatewayConfiguration.official
    )
    private let activationStore = HTMLAppPushActivationStore()
    private let presentationMetadataStore = HTMLAppPresentationMetadataStore()
    private lazy var launchResolver = DrelHTMLAppLaunchSupport.makeResolver(trustRegistry: runtime.trustRegistry)
    private lazy var onboardingService = DrelOAuthGatewayAuthorizationIntegration(
        gatewayRegistry: gatewayRegistry,
        trustRegistry: runtime.trustRegistry,
        permissionLedger: runtime.permissionLedger,
        presentationMetadataStore: presentationMetadataStore
    )
    private var manifestsByID: [String: HTMLAppManifest] = [:]
    private var viewModel: PWAAppCatalogViewModel?
    private var isRefreshingCatalog = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeTokens.Color.background
        reload()
        refreshCatalogIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // PWAAppCenter hides the shared navigation bar on its own root screen.
        // The catalog is a pushed child, so it must restore the bar when a web
        // app is closed or the user otherwise returns here.
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if navigationItem.leftBarButtonItem == nil,
           (navigationController?.viewControllers.count ?? 0) > 1 {
            let back = UIBarButtonItem(
                image: LucideIcon.chevronLeft.image(),
                style: .plain,
                target: self,
                action: #selector(backToAppCenter)
            )
            back.accessibilityIdentifier = "pwaCatalog.back"
            back.accessibilityLabel = "返回我的应用"
            back.tintColor = ThemeTokens.Color.text
            navigationItem.leftBarButtonItem = back
        }
    }

    @objc private func backToAppCenter() {
        navigationController?.popViewController(animated: true)
    }

    private func reload() {
        let manifests = runtime.trustRegistry.registeredManifests()
            .filter { $0.signature != nil }
            .sorted {
                let leftActive = activationStore.contains($0.appID)
                let rightActive = activationStore.contains($1.appID)
                if leftActive != rightActive { return leftActive && !rightActive }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        manifestsByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.appID, $0) })
        let items = manifests.map(makeCatalogItem)
        let gatewayName = gatewayRegistry.activeGateway()?.name ?? "当前应用服务"

        if let viewModel {
            viewModel.apps = items
            viewModel.gatewayName = gatewayName
        } else {
            let viewModel = PWAAppCatalogViewModel(apps: items, gatewayName: gatewayName)
            self.viewModel = viewModel
            install(viewModel)
        }
    }

    private func install(_ viewModel: PWAAppCatalogViewModel) {
        let rootView = PWAAppCatalogView(
            viewModel: viewModel,
            onOpen: { [weak self] item in self?.open(item) },
            onAddToHome: { [weak self] item in self?.addToHome(item) }
        )
        let hosting = UIHostingController(rootView: rootView)
        hosting.navigationItem.title = "全部应用"
        hosting.view.backgroundColor = ThemeTokens.Color.background
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func refreshCatalogIfNeeded() {
        guard manifestsByID.isEmpty, !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        let gateway = gatewayRegistry.activeGateway() ?? DrelGatewayConfiguration.official
        onboardingService.validate(gateway) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshingCatalog = false
                guard case .success(let report) = result else { return }
                do {
                    try self.onboardingService.activate(report)
                    self.reload()
                } catch {
                    // The empty state remains visible; the home screen owns
                    // the gateway error presentation and retry cooldown.
                }
            }
        }
    }

    private func makeCatalogItem(_ manifest: HTMLAppManifest) -> PWAAppCatalogItem {
        let metadata = presentationMetadataStore.metadata(for: manifest.appID)
        let displayName = metadata?.name ?? manifest.name
        let sourceHost = URL(string: manifest.startURL)?.host
            ?? manifest.allowedOrigins.first
            ?? "未知来源"
        let signature = manifest.signature

        var capabilities = manifest.capabilitiesV2.map { declaration in
            PWAAppCatalogItem.Capability(
                id: "v2.\(declaration.purposeId)",
                title: actionTitle(declaration.action),
                detail: "\(declaration.purpose) · \(scopeTitle(declaration.scope))"
            )
        }
        for capability in manifest.capabilities {
            let id = "v1.\(capability.rawValue)"
            if !capabilities.contains(where: { $0.id == id }) {
                capabilities.append(
                    PWAAppCatalogItem.Capability(
                        id: id,
                        title: capability.displayName,
                        detail: "旧版能力声明"
                    )
                )
            }
        }

        return PWAAppCatalogItem(
            id: manifest.appID,
            name: displayName,
            iconURL: metadata?.iconURLs.last,
            iconCacheKey: "\(manifest.appID)|\(manifest.webManifest?.sha256 ?? "no-web-manifest")",
            fallbackInitial: appInitial(displayName, appID: manifest.appID),
            tint: appTint(manifest.appID),
            version: manifest.effectiveOfflineCache.version,
            sourceHost: sourceHost,
            sourceOrigins: manifest.allowedOrigins,
            signatureAlgorithm: signature?.algorithm ?? "未签名",
            signatureKeyID: signature?.keyID ?? "未知",
            startURL: manifest.startURL,
            routes: manifest.routes,
            offlineSummary: offlineSummary(manifest),
            capabilities: capabilities,
            isActivated: activationStore.contains(manifest.appID)
        )
    }

    private func open(_ item: PWAAppCatalogItem) {
        guard let manifest = manifestsByID[item.id],
              let startURL = URL(string: manifest.startURL) else { return }
        Task { @MainActor in
            guard let slotOwner = DrelHTMLAppLaunchSupport.acquireLaunchSlot(appID: manifest.appID, route: startURL.path, parameters: [:], sourceID: "catalog." + item.id) else { return }
            defer { DrelHTMLAppLaunchSupport.releaseLaunchSlot(owner: slotOwner) }
            do {
                let target = try await DrelHTMLAppLaunchSupport.resolveWithColdStartGate {
                    try launchResolver.resolve(
                        appID: manifest.appID,
                        route: startURL.path,
                        networkPolicy: DrelHTMLAppLaunchSupport.networkPolicy
                    )
                }
                let diagnostics = OfflineAppDiagnosticsCoordinator.recordLaunchSuccess(target, source: "catalog")
                DrelHTMLAppLaunchSupport.presentImmersive(target, diagnostics: diagnostics, from: self)
            } catch {
                OfflineAppDiagnosticsCoordinator.recordLaunchResolutionFailure(
                    appID: item.id,
                    source: "catalog",
                    error: error
                )
                showMessage(title: "无法打开应用", message: error.localizedDescription)
            }
        }
    }

    private func addToHome(_ item: PWAAppCatalogItem) {
        guard item.isActivated == false else { return }
        activationStore.activate(item.id)
        reload()
        HUDService.shared.showSuccess(withStatus: "\(item.name) 已添加到首页")
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func actionTitle(_ action: HTMLAppControlledAction) -> String {
        switch action {
        case .haptic: return "触感反馈"
        case .vibrate: return "震动"
        case .share: return "系统分享"
        case .fullscreen: return "沉浸全屏"
        case .clipboard: return "剪贴板"
        case .getLocation: return "当前位置"
        case .addToHomeScreen: return "添加到主页"
        case .sensors: return "运动传感器"
        case .audioLevel: return "麦克风音量"
        }
    }

    private func scopeTitle(_ scope: HTMLAppPermissionScope) -> String {
        switch scope {
        case .once: return "仅本次"
        case .appSession: return "应用会话"
        case .always: return "始终允许"
        }
    }

    private func offlineSummary(_ manifest: HTMLAppManifest) -> String {
        let cache = manifest.effectiveOfflineCache
        if cache.isStrongOfflineEligible {
            return cache.persistent ? "强离线 · \(cache.version)" : "离线 · \(cache.version)"
        }
        return cache.strategy == .networkOnly ? "在线应用" : "缓存优先 · \(cache.version)"
    }

    private func appInitial(_ name: String, appID: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first { return String(first).uppercased() }
        let component = appID.split(separator: ".").last.map(String.init) ?? appID
        return component.first.map { String($0).uppercased() } ?? "A"
    }

    private func appTint(_ appID: String) -> UIColor {
        let value = appID.unicodeScalars.reduce(0) { partial, scalar in
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
