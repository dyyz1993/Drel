import SwiftUI
import UIKit
import WebBridgeKit

struct PhoneHomeScreenGuideView: View {
    let appName: String
    let iconURL: URL?
    let iconCacheKey: String
    let fallbackInitial: String
    let tint: UIColor
    let homeEntryURL: URL
    let onOpenEntry: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var icon: UIImage?
    @State private var openedEntry = false
    @State private var appeared = false

    private let ink = Color.appText
    private let muted = Color.appTextSecondary
    private let accent = Color.appPrimary

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    appIdentity
                    illustration
                        .frame(maxWidth: .infinity)
                        .frame(height: 104)
                        .accessibilityHidden(true)
                    safetyNote
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            actions
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task(id: iconCacheKey) {
            icon = nil
            guard let iconURL,
                  let data = await PWAAppIconLoader.shared.data(for: iconURL, cacheKey: iconCacheKey) else { return }
            icon = UIImage(data: data)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            }
        }
        .accessibilityIdentifier("homeShortcut.guide")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("放到 iPhone 主屏幕")
                    .font(.title2.weight(.bold))
                    .foregroundColor(ink)
                Text("用 Safari 添加这个应用的主屏幕入口")
                    .font(.subheadline)
                    .foregroundColor(muted)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(muted)
                    .frame(width: 36, height: 36)
                    .background(Color.appText.opacity(0.07), in: Circle())
            }
            .accessibilityLabel("关闭引导")
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(Color(tint).opacity(0.13))
                if let icon {
                    Image(uiImage: icon).resizable().scaledToFit().padding(4)
                } else {
                    Text(fallbackInitial)
                        .font(.title2.weight(.bold))
                        .foregroundColor(Color(tint))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(appName).font(.subheadline.weight(.semibold)).foregroundColor(ink).lineLimit(1)
                Text(icon == nil ? "暂用首字母占位；Safari 添加前可确认图标" : "Safari 将使用这个应用图标")
                    .font(.caption).foregroundColor(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.appText.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [accent.opacity(0.16), Color(ThemeTokens.Color.accent).opacity(0.11), Color.appBackground], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(accent.opacity(0.11), lineWidth: 1).frame(width: 220).offset(x: 120, y: -80)
            Circle().stroke(accent.opacity(0.11), lineWidth: 1).frame(width: 290).offset(x: 120, y: -80)
            workflowIllustration
        }
        .clipped()
    }

    private var workflowIllustration: some View {
        VStack(spacing: 4) {
            shortcutBlock(iconName: "square.and.arrow.up", title: "1 · 点分享按钮", subtitle: "Safari 底部中间的分享图标")
            Image(systemName: "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundColor(accent)
            shortcutBlock(iconName: "square.grid.2x2", title: "2 · 点“添加到主屏幕”", subtitle: "菜单里往下滑，点这一行")
        }
        .padding(.horizontal, 22)
    }

    private func shortcutBlock(iconName: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName).font(.subheadline).foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.bold)).foregroundColor(ink)
                Text(subtitle).font(.caption).foregroundColor(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: 310)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 单行安全声明：medium 半屏也要完整可见，正文说明全部并入图示与按钮副文案。
    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
            Text("添加动作由 Safari 和你确认；Drel 不能静默安装主屏幕图标。")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(accent)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("homeShortcut.instructions")
    }

    /// 合并后的单一主按钮（2026-10-21 用户验收）：点击「打开 Safari 入口页」
    /// 后原位变为「我已添加，完成」，再点一次完成关闭。
    private var actions: some View {
        VStack(spacing: 8) {
            if openedEntry {
                Button(action: onClose) {
                    Label("我已添加，完成", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("homeShortcut.finish")
            } else {
                Button {
                    onOpenEntry()
                    openedEntry = true
                } label: {
                    Label("打开 Safari 入口页", systemImage: "safari")
                }
                .accessibilityIdentifier("homeShortcut.openEntry")
            }
            Text(openedEntry
                ? "已在 Safari 打开入口页。完成「添加到主屏幕」后，点上面的完成。"
                : "入口链接已自动复制；打开 Safari 后点底部「分享」→「添加到主屏幕」。")
                .font(.caption)
                .foregroundColor(muted)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(GuideButtonStyle())
    }
}

private struct GuideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundColor(Color.appPrimary)
            .background(Color(ThemeTokens.Color.primarySoft), in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// iPhone 主屏幕添加引导的唯一呈现入口：应用中心长按菜单与网页
/// `addToHomeScreen {placement:"phoneHomeScreen"}` 动作共用同一张弹窗。
enum PhoneHomeScreenGuidePresenter {

    static func present(from presenter: UIViewController, manifest: HTMLAppManifest) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "drel.app"
        components.path = "/launch/"
        let metadata = HTMLAppPresentationMetadataStore().metadata(for: manifest.appID)
        let displayName = metadata?.name ?? manifest.name
        var queryItems = [
            URLQueryItem(name: "app_id", value: manifest.appID),
            URLQueryItem(name: "name", value: displayName)
        ]
        if let iconURL = metadata?.iconURLs.last,
           iconURL.scheme?.lowercased() == "https" {
            queryItems.append(URLQueryItem(name: "icon", value: iconURL.absoluteString))
        }
        if let startURL = URL(string: manifest.startURL),
           let route = URLComponents(url: startURL, resolvingAgainstBaseURL: false)?.path,
           route != "/" {
            queryItems.append(URLQueryItem(name: "route", value: route))
        }
        components.queryItems = queryItems
        guard let entryURL = components.url else { return }
        UIPasteboard.general.url = entryURL
        let guide = PhoneHomeScreenGuideView(
            appName: displayName,
            iconURL: metadata?.iconURLs.last,
            iconCacheKey: "\(manifest.appID)|\(manifest.webManifest?.sha256 ?? "no-web-manifest")",
            fallbackInitial: appInitial(name: displayName, appID: manifest.appID),
            tint: appTint(for: manifest),
            homeEntryURL: entryURL,
            onOpenEntry: { UIApplication.shared.open(entryURL) },
            onClose: { presenter.dismiss(animated: true) }
        )
        let host = UIHostingController(rootView: guide)
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            // 默认半屏（medium）：内容按半屏高度精简设计，整屏显得突兀
            // （2026-10-21 用户反馈「顶多半屏」）。内容溢出时可下拉/上拉。
            sheet.selectedDetentIdentifier = .medium
        }
        presenter.present(host, animated: true)
    }

    private static func appInitial(name: String, appID: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmedName.first { return String(first).uppercased() }
        let appComponent = appID.split(separator: ".").last.map(String.init) ?? appID
        if let first = appComponent.first { return String(first).uppercased() }
        return "D"
    }

    private static func appTint(for manifest: HTMLAppManifest) -> UIColor {
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
