import SwiftUI
import WebBridgeKit

/// Selects a trusted HTML app whose manifest start URL should open on Drel's
/// next cold launch. Only the app ID is stored; routes and query parameters are
/// deliberately excluded from this preference.
struct DefaultStartupAppView: View {
    @AppStorage(SettingsPreferenceKeys.defaultStartupAppID) private var defaultStartupAppID = ""
    @State private var manifests: [HTMLAppManifest] = []

    var body: some View {
        List {
            Section {
                Text("选择后，Drel 会在下次冷启动时打开该应用的首页。推送仍会优先打开推送指定的页面。")
                    .font(Font.app(ThemeTokens.Typography.metadata))
                    .foregroundColor(Color.appTextSecondary)
                    .accessibilityIdentifier("defaultStartupApp.explanation")
            }

            if manifests.isEmpty {
                Section {
                    Text("还没有可选应用。请先在“应用中心”连接并添加一个网页应用。")
                        .font(Font.app(ThemeTokens.Typography.body))
                        .foregroundColor(Color.appTextSecondary)
                        .accessibilityIdentifier("defaultStartupApp.empty")
                }
            } else {
                Section("我的应用") {
                    ForEach(manifests, id: \.appID) { manifest in
                        Button {
                            defaultStartupAppID = manifest.appID
                        } label: {
                            HStack(spacing: ThemeTokens.Spacing.md) {
                                ManifestIconView(manifest: manifest)

                                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
                                    Text(manifest.name)
                                        .font(Font.app(ThemeTokens.Typography.rowTitle))
                                        .foregroundColor(Color.appText)
                                    Text(manifest.appID)
                                        .font(Font.app(ThemeTokens.Typography.metadata))
                                        .foregroundColor(Color.appTextSecondary)
                                }

                                Spacer()

                                if defaultStartupAppID == manifest.appID {
                                    Image(uiImage: LucideIcon.check.templateImage(pointSize: ThemeTokens.Icons.Sizes.sm) ?? UIImage())
                                        .renderingMode(.template)
                                        .foregroundColor(Color.appPrimary)
                                        .accessibilityIdentifier("defaultStartupApp.selected.\(manifest.appID)")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("defaultStartupApp.option.\(manifest.appID)")
                    }
                }

                if !defaultStartupAppID.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            defaultStartupAppID = ""
                        } label: {
                            Text("不设默认启动应用")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("defaultStartupApp.clear")
                    }
                }
            }
        }
        .appListStyle()
        .navigationTitle("默认启动应用")
        .accessibilityIdentifier("defaultStartupApp.root")
        .onAppear(perform: reloadApps)
    }

    private func reloadApps() {
        manifests = HTMLAppRuntimeCenter.shared.trustRegistry.registeredManifests()
        if !defaultStartupAppID.isEmpty,
           !manifests.contains(where: { $0.appID == defaultStartupAppID }) {
            defaultStartupAppID = ""
        }
    }
}

/// 行图标：manifest 声明的签名图标优先（与首页同源同磁盘缓存），未取到时
/// 回退到模板图标。对齐收藏夹 cell 的「真实图标 + 兜底」取值方式。
private struct ManifestIconView: View {
    let manifest: HTMLAppManifest
    @State private var icon: UIImage?

    var body: some View {
        ZStack {
            if let icon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: LucideIcon.appFill.templateImage(pointSize: ThemeTokens.Icons.Sizes.md) ?? UIImage())
                    .renderingMode(.template)
                    .foregroundColor(Color.appPrimary)
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(ThemeTokens.Color.primarySoft))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.CornerRadius.sm))
        .task(id: manifest.appID) {
            let metadata = HTMLAppPresentationMetadataStore().metadata(for: manifest.appID)
            guard let iconURL = metadata?.iconURLs.last else { return }
            let cacheKey = "\(manifest.appID)|\(manifest.webManifest?.sha256 ?? "no-web-manifest")"
            if let data = await PWAAppIconLoader.shared.data(for: iconURL, cacheKey: cacheKey) {
                icon = UIImage(data: data)
            }
        }
    }
}
