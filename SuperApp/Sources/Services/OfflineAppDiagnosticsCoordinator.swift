import Foundation
import WebBridgeKit

enum OfflineAppDiagnosticsCoordinator {
    private static let packageLocator = HTMLAppOfflinePackageLocator()

    static func begin(
        manifest: HTMLAppManifest,
        source: String
    ) -> WebBrowserParams.OfflineDiagnosticsContext {
        let cache = manifest.effectiveOfflineCache
        let attempt = DrelOfflineDiagnostics.shared.beginAttempt(
            appID: manifest.appID,
            packageVersion: cache.version,
            manifestDigestPrefix: cache.resourceManifestSHA256,
            source: source
        )
        recordPackageState(for: manifest, attemptID: attempt.id)
        return WebBrowserParams.OfflineDiagnosticsContext(
            attemptID: attempt.id,
            appID: manifest.appID,
            packageVersion: cache.version,
            manifestDigestPrefix: cache.resourceManifestSHA256,
            source: source
        )
    }

    static func recordLaunchFailure(
        manifest: HTMLAppManifest,
        attemptID: String?,
        error: Error
    ) {
        DrelOfflineDiagnostics.shared.record(
            attemptID: attemptID ?? "",
            phase: .launch,
            status: .failed,
            loadSource: .unknown,
            error: error,
            outcome: nil
        )
    }

    static func recordLaunchResolutionFailure(
        appID: String,
        source: String,
        error: Error
    ) {
        let attempt = DrelOfflineDiagnostics.shared.beginAttempt(
            appID: appID,
            packageVersion: nil,
            manifestDigestPrefix: nil,
            source: source
        )
        DrelOfflineDiagnostics.shared.record(
            attemptID: attempt.id,
            phase: .launch,
            status: .failed,
            loadSource: .unknown,
            error: error
        )
    }

    private static func recordPackageState(for manifest: HTMLAppManifest, attemptID: String) {
        let cache = manifest.effectiveOfflineCache
        guard let installed = try? packageLocator.installedPackage(appID: manifest.appID) else {
            DrelOfflineDiagnostics.shared.record(
                attemptID: attemptID,
                phase: .package,
                status: .failed,
                loadSource: .online,
                outcome: "packageMissing"
            )
            return
        }

        guard installed.version == cache.version,
              installed.resourceManifestSHA256 == cache.resourceManifestSHA256,
              (try? packageLocator.entrypointURL(for: installed)) != nil else {
            DrelOfflineDiagnostics.shared.record(
                attemptID: attemptID,
                phase: .package,
                status: .failed,
                loadSource: .online,
            outcome: installed.version != cache.version
                ? "versionMismatch"
                : installed.resourceManifestSHA256 != cache.resourceManifestSHA256
                    ? "digestMismatch"
                    : "entrypointMissing"
            )
            return
        }

        DrelOfflineDiagnostics.shared.record(
            attemptID: attemptID,
            phase: .package,
            status: .succeeded,
            loadSource: .offlinePackage,
            outcome: "packageFound"
        )
    }
}
