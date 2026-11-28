import Foundation
import WebBridgeKit

extension PWAAppCenterViewController {
    static func gatewayFailure(for error: Error) -> (title: String, message: String) {
        let title = L10n.tr("home.apps.gateway_failure_title")
        let message: String

        if error is URLError {
            message = L10n.tr("home.apps.failure.network")
        } else if let error = error as? HTMLAppGatewayOnboardingError {
            switch error {
            case .invalidHealthResponse(let statusCode), .invalidManifestResponse(let statusCode):
                message = (500...599).contains(statusCode)
                    ? L10n.tr("home.apps.failure.server")
                    : L10n.tr("home.apps.failure.generic")
            case .invalidManifest, .signatureVerificationFailed:
                message = L10n.tr("home.apps.failure.manifest")
            default:
                message = L10n.tr("home.apps.failure.generic")
            }
        } else {
            message = L10n.tr("home.apps.failure.generic")
        }

        return (title, message)
    }

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
