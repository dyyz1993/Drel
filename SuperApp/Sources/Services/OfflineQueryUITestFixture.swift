#if DEBUG
import CryptoKit
import Foundation
import WebBridgeKit

/// Deterministic local package for simulator UI tests only.
enum OfflineQueryUITestFixture {
    static func install(appID: String) {
        let id = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        let appRoot = HTMLAppOfflinePackageLocator.defaultPackagesRoot.appendingPathComponent(id)
        let root = appRoot.appendingPathComponent("versions/ui-test-v1")
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:64px 32px} button{min-height:56px;min-width:220px}</style></head><body><button onclick="query()">查询离线能力</button><p id="result">等待查询</p>
        <script>async function query(){try{const r=await window.BarkBridge.callNative('getCapabilities',{});
        const c=r.data.actions.clipboard;document.querySelector('#result').textContent=
        '离线查询 '+c.supported+' '+c.declared+' '+c.appPermission;}catch(e){document.querySelector('#result').textContent='离线查询失败';}}</script>
        </body></html>
        """
        let package = InstalledHTMLAppPackage(appID: appID, version: "offline-query-v1", entrypoint: "index.html",
            directoryName: "ui-test-v1", resourceManifestSHA256: String(repeating: "a", count: 64), installedAt: Date())
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: root.appendingPathComponent("index.html"), options: .atomic)
            let data = try JSONEncoder().encode(package)
            try data.write(to: root.appendingPathComponent("package.json"), options: .atomic)
            try data.write(to: appRoot.appendingPathComponent("current.json"), options: .atomic)
        } catch { assertionFailure("Offline UI fixture failed: \(error)") }
    }
}
#endif
