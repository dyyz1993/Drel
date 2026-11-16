#if DEBUG
import CryptoKit
import Foundation
import WebBridgeKit

enum OfflineVOTUITestFixture {
    private struct PackageManifest: Codable {
        let version: String
        let entrypoint: String
        let files: [File]

        struct File: Codable {
            let path: String
            let url: String
            let size: Int
        }
    }

    private static let identities = [
        "app.vot.19930810.xyz",
        "app.vot.shanbox.19930810.xyz"
    ]
    private static let origin = "https://vot.19930810.xyz:8443"
    private static let packageURL = URL(
        string: "\(origin)/drel/v0.4.10.3/package.json"
    )!

    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--register-vot-offline-fixtures") else { return }
        do {
            try install()
        } catch {
            StructuredLogger.shared.error(
                "Unable to install VOT offline fixtures: \(error.localizedDescription)",
                category: .navigation
            )
        }
    }

    private static func install() throws {
        let manifestData = try data(from: packageURL)
        let manifest = try JSONDecoder().decode(PackageManifest.self, from: manifestData)
        let digest = sha256(manifestData)
        let files = try manifest.files.map { file in
            try (path: file.path, data: data(from: URL(string: file.url).unwrap()))
        }

        for appID in identities {
            let appRoot = HTMLAppOfflinePackageLocator.defaultPackagesRoot
                .appendingPathComponent(sha256(appID), isDirectory: true)
            let versionRoot = appRoot
                .appendingPathComponent("versions/\(manifest.version)-\(digest.prefix(16))", isDirectory: true)
            try FileManager.default.createDirectory(
                at: versionRoot,
                withIntermediateDirectories: true
            )
            for file in files {
                let destination = versionRoot.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.data.write(to: destination, options: .atomic)
            }
            let installed = InstalledHTMLAppPackage(
                appID: appID,
                version: manifest.version,
                entrypoint: manifest.entrypoint,
                directoryName: "\(manifest.version)-\(digest.prefix(16))",
                resourceManifestSHA256: digest,
                installedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try manifestData.write(
                to: versionRoot.appendingPathComponent("package.json"),
                options: .atomic
            )
            try encoder.encode(installed).write(
                to: appRoot.appendingPathComponent("installed.json"),
                options: .atomic
            )
            try encoder.encode(installed).write(
                to: appRoot.appendingPathComponent("current.json"),
                options: .atomic
            )

            let entryPath = "/drel/v0.4.10.3/\(manifest.entrypoint)"
            let appManifest = HTMLAppManifest(
                appID: appID,
                name: appID == identities[0] ? "VOT 0.4.10.3" : "VOT Legacy",
                startURL: "\(origin)\(entryPath)",
                allowedOrigins: [origin],
                capabilities: [],
                routes: ["/", entryPath],
                cache: HTMLAppCachePolicy(
                    strategy: .manifest,
                    version: manifest.version,
                    persistent: true,
                    resourceManifestURL: packageURL.absoluteString,
                    resourceManifestSHA256: digest
                )
            )
            try HTMLAppRuntimeCenter.shared.register(appManifest)
            HTMLAppPushActivationStore().activate(appID)
        }

        if ProcessInfo.processInfo.arguments.contains("--vot-white-screen-fixture") {
            let entrypoint = HTMLAppOfflinePackageLocator.defaultPackagesRoot
                .appendingPathComponent(sha256(identities[0]), isDirectory: true)
                .appendingPathComponent("versions/\(manifest.version)-\(digest.prefix(16))")
                .appendingPathComponent(manifest.entrypoint)
            try Data("<html><body></body></html>".utf8)
                .write(to: entrypoint, options: .atomic)
        }
    }

    private static func data(from url: URL) throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var requestError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            result = data
            requestError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let requestError { throw requestError }
        guard let result, !result.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw URLError(.badURL) }
        return self
    }
}
#endif
