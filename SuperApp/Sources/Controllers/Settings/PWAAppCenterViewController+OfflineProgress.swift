import UIKit
import WebBridgeKit

extension PWAAppCenterViewController {
    static func offlinePackageProgressUpdate(
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
}
