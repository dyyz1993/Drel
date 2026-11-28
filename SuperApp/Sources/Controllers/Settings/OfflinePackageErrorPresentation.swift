import Foundation
import WebBridgeKit

extension PWAAppCenterViewController {
    static func message(for error: HTMLAppOfflinePackageError) -> String {
        switch error {
        case .transportFailed:
            return L10n.tr("home.apps.offline.network")
        case .invalidResourceManifestDigest,
             .resourceManifestTooLarge,
             .resourceManifestDigestMismatch,
             .invalidResourceManifest,
             .identityMismatch,
             .invalidFileDigest,
             .invalidFileSize,
             .fileTooLarge,
             .packageTooLarge,
             .fileSizeMismatch,
             .fileDigestMismatch:
            return L10n.tr("home.apps.offline.validation")
        case .parentManifestNotEligible,
             .unsupportedSchemaVersion,
             .emptyPackage,
             .tooManyFiles,
             .invalidPath,
             .duplicatePath,
             .pathConflict,
             .missingEntrypoint,
             .invalidURL,
             .disallowedOrigin:
            return L10n.tr("home.apps.offline.structure")
        case .persistenceFailed, .noInstalledPackage:
            return L10n.tr("home.apps.offline.generic")
        }
    }
}
