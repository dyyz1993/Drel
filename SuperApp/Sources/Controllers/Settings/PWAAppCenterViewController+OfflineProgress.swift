import UIKit
import WebBridgeKit

extension PWAAppCenterViewController {
    nonisolated static func offlinePackageProgressUpdate(
        _ progress: HTMLAppPackageProgress
    ) -> (progress: Float, status: String)? {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        switch progress {
        case .downloadingManifest:
            return (0, "正在下载离线清单…")
        case .validatingManifest:
            return (0, "正在校验离线清单…")
        case let .packageSize(totalBytes, fileCount):
            return (0, "预计下载 \(formatter.string(fromByteCount: totalBytes))（\(fileCount) 个文件）")
        case let .downloadingFile(current, total, _):
            let ratio = Float(current - 1) / Float(max(total, 1))
            return (min(max(ratio, 0), 1), "正在下载 \(current)/\(total)")
        case let .downloadProgress(
            current,
            total,
            _,
            _,
            _,
            packageBytesWritten,
            packageTotalBytes
        ):
            let ratio = packageTotalBytes > 0
                ? Float(Double(packageBytesWritten) / Double(packageTotalBytes))
                : 0
            return (
                min(max(ratio, 0), 1),
                "正在下载 \(current)/\(total) · \(formatter.string(fromByteCount: packageBytesWritten)) / \(formatter.string(fromByteCount: packageTotalBytes))"
            )
        case let .validatingFile(current, total, _):
            return (0, "正在校验 \(current)/\(total)")
        case .activating:
            return (1, "正在激活离线包…")
        case .completed:
            return (1, "离线包准备完成")
        case .usingPreviousVersion:
            return (0, "更新失败，保留旧版本")
        }
    }

    func hasCurrentOfflinePackage(for manifest: HTMLAppManifest) -> Bool {
        guard let package = try? offlinePackageLocator.installedPackage(appID: manifest.appID) else {
            return false
        }
        let cache = manifest.effectiveOfflineCache
        return package.version == cache.version
            && package.resourceManifestSHA256 == cache.resourceManifestSHA256
            && (try? offlinePackageLocator.entrypointURL(for: package)) != nil
    }

    func offlinePackageSummary(for manifest: HTMLAppManifest) -> String {
        let cache = manifest.effectiveOfflineCache
        guard cache.isStrongOfflineEligible else {
            return cache.restoresLastState ? "缓存优先（\(cache.version)）" : "在线"
        }

        guard let package = try? offlinePackageLocator.installedPackage(appID: manifest.appID) else {
            return "强离线包待准备（可下载后离线打开，\(cache.version)）"
        }
        guard hasCurrentOfflinePackage(for: manifest) else {
            return "强离线包待更新（当前 \(package.version) → \(cache.version)）"
        }
        let size = (try? offlinePackageLocator.packageSize(for: package)) ?? 0
        return "强离线包已安装（\(cache.version)，\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))）"
    }
}
