import Crypto
import Foundation
import Hummingbird
import Testing

@testable import WebBridgeServer

@Suite("HTML App Capabilities V2")
struct HTMLAppCapabilitiesV2Tests {
    private let rawPrivateKey = Data(repeating: 9, count: 32)

    @Test("Signs every action declaration field")
    func signsEveryField() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)

        let signed = try await service.save(manifest())
        let gateway = try await service.gatewayConfiguration()
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: decodeBase64URL(gateway.publicKey)!
        )
        let signature = try #require(signed.signature)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(signed.unsigned())
        let signatureData = try #require(decodeBase64URL(signature.value))
        #expect(publicKey.isValidSignature(signatureData, for: payload))
        #expect(signed.capabilitiesV2 == [declaration()])
    }

    @Test("Rejects always for non-grant actions")
    func rejectsAlwaysForNonGrantAction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = HTMLAppPolicyManifest(
            schemaVersion: "1",
            appId: "com.example.actions",
            name: "Actions",
            startURL: "https://apps.example.com/actions/index.html",
            allowedOrigins: ["https://apps.example.com"],
            capabilities: [],
            capabilitiesV2: [
                HTMLAppPolicyManifest.CapabilityDeclaration(
                    action: .share,
                    origins: ["https://apps.example.com"],
                    purposeId: "share-report",
                    purpose: "Share the selected report",
                    scope: .always
                )
            ],
            routes: ["/actions/index.html"],
            cache: .init(strategy: .networkOnly, version: "1", persistent: false),
            signature: nil
        )
        let service = makeService(dataDir: directory.path)
        await #expect(throws: HTTPError.self) {
            try await service.save(manifest)
        }
    }

    @Test("Accepts always for clipboard and location grants")
    func acceptsAlwaysForGrantAction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = HTMLAppPolicyManifest(
            schemaVersion: "1",
            appId: "com.example.grants",
            name: "Grants",
            startURL: "https://apps.example.com/grants/index.html",
            allowedOrigins: ["https://apps.example.com"],
            capabilities: [],
            capabilitiesV2: [
                HTMLAppPolicyManifest.CapabilityDeclaration(
                    action: .clipboard,
                    origins: ["https://apps.example.com"],
                    purposeId: "clipboard-grant",
                    purpose: "Read or write clipboard content",
                    scope: .always
                ),
                HTMLAppPolicyManifest.CapabilityDeclaration(
                    action: .location,
                    origins: ["https://apps.example.com"],
                    purposeId: "location-grant",
                    purpose: "Get the current position",
                    scope: .always
                )
            ],
            routes: ["/grants/index.html"],
            cache: .init(strategy: .networkOnly, version: "1", persistent: false),
            signature: nil
        )
        let service = makeService(dataDir: directory.path)
        let signed = try await service.save(manifest)
        #expect(signed.capabilitiesV2.count == 2)
    }

    @Test("Rejects unknown action")
    func rejectsUnknownAction() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "schemaVersion": "1",
          "appId": "com.example.actions",
          "name": "Actions",
          "startURL": "https://apps.example.com/actions/index.html",
          "allowedOrigins": ["https://apps.example.com"],
          "capabilities": [],
          "capabilities_v2": [{
            "action": "notARealAction",
            "origins": ["https://apps.example.com"],
            "purposeId": "share-report",
            "purpose": "Share the selected report",
            "scope": "always"
          }],
          "routes": ["/actions/index.html"],
          "cache": {"strategy":"networkOnly","version":"1","persistent":false}
        }
        """
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HTMLAppPolicyManifest.self, from: Data(json.utf8))
        }
    }

    @Test("Rejects origin outside parent manifest")
    func rejectsOriginOutsideParent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)
        var invalid = manifest()
        invalid = HTMLAppPolicyManifest(
            schemaVersion: invalid.schemaVersion,
            appId: invalid.appId,
            name: invalid.name,
            startURL: invalid.startURL,
            allowedOrigins: invalid.allowedOrigins,
            capabilities: invalid.capabilities,
            capabilitiesV2: [
                HTMLAppPolicyManifest.CapabilityDeclaration(
                    action: .share,
                    origins: ["https://attacker.example"],
                    purposeId: "share-report",
                    purpose: "Share the selected report",
                    scope: .once
                )
            ],
            routes: invalid.routes,
            cache: invalid.cache,
            signature: nil
        )

        await #expect(throws: HTTPError.self) {
            try await service.save(invalid)
        }
    }

    @Test("Rejects duplicate purpose IDs")
    func rejectsDuplicatePurposeIDs() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)
        let declaration = declaration()
        let invalid = HTMLAppPolicyManifest(
            schemaVersion: "1",
            appId: "com.example.actions",
            name: "Actions",
            startURL: "https://apps.example.com/actions/index.html",
            allowedOrigins: ["https://apps.example.com"],
            capabilities: [],
            capabilitiesV2: [declaration, declaration],
            routes: ["/actions/index.html"],
            cache: .init(strategy: .networkOnly, version: "1", persistent: false),
            signature: nil
        )

        await #expect(throws: HTTPError.self) {
            try await service.save(invalid)
        }
    }

    @Test("Rejects empty or oversized purpose metadata")
    func rejectsInvalidPurposeMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)

        for purpose in ["", String(repeating: "x", count: 161)] {
            let invalid = manifest(purpose: purpose)
            await #expect(throws: HTTPError.self) {
                try await service.save(invalid)
            }
        }
    }

    @Test("Legacy capability arrays do not create action declarations")
    func legacyArraysDoNotCreateDeclarations() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)
        let candidate = HTMLAppPolicyManifest(
            schemaVersion: "1",
            appId: "com.example.legacy",
            name: "Legacy",
            startURL: "https://apps.example.com/legacy/index.html",
            allowedOrigins: ["https://apps.example.com"],
            capabilities: [.share],
            routes: ["/legacy/index.html"],
            cache: .init(strategy: .networkOnly, version: "1", persistent: false),
            signature: nil
        )

        let signed = try await service.save(candidate)
        #expect(signed.capabilities.isEmpty == false)
        #expect(signed.capabilitiesV2.isEmpty)
    }

    @Test("Tampering any declaration field breaks signature")
    func tamperingBreaksSignature() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(dataDir: directory.path)
        let signed = try await service.save(manifest())
        let original = try #require(signed.capabilitiesV2.first)

        let tamperedDeclarations: [HTMLAppPolicyManifest.CapabilityDeclaration] = [
            HTMLAppPolicyManifest.CapabilityDeclaration(
                action: .haptic, origins: original.origins, purposeId: original.purposeId,
                purpose: original.purpose, scope: original.scope
            ),
            HTMLAppPolicyManifest.CapabilityDeclaration(
                action: original.action, origins: ["https://other.example.com"],
                purposeId: original.purposeId, purpose: original.purpose, scope: original.scope
            ),
            HTMLAppPolicyManifest.CapabilityDeclaration(
                action: original.action, origins: original.origins, purposeId: "other-purpose",
                purpose: original.purpose, scope: original.scope
            ),
            HTMLAppPolicyManifest.CapabilityDeclaration(
                action: original.action, origins: original.origins, purposeId: original.purposeId,
                purpose: "Tampered purpose", scope: original.scope
            ),
            HTMLAppPolicyManifest.CapabilityDeclaration(
                action: original.action, origins: original.origins, purposeId: original.purposeId,
                purpose: original.purpose, scope: .appSession
            )
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let gateway = try await service.gatewayConfiguration()
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: decodeBase64URL(gateway.publicKey)!
        )
        let signature = try #require(signed.signature)
        let signatureData = try #require(decodeBase64URL(signature.value))

        for tampered in tamperedDeclarations {
            let tamperedManifest = HTMLAppPolicyManifest(
                schemaVersion: signed.schemaVersion,
                appId: signed.appId,
                name: signed.name,
                startURL: signed.startURL,
                allowedOrigins: signed.allowedOrigins,
                capabilities: signed.capabilities,
                capabilitiesV2: [tampered],
                routes: signed.routes,
                cache: signed.cache,
                signature: nil
            )
            #expect(!publicKey.isValidSignature(signatureData, for: try encoder.encode(tamperedManifest)))
        }
    }

    private func declaration() -> HTMLAppPolicyManifest.CapabilityDeclaration {
        HTMLAppPolicyManifest.CapabilityDeclaration(
            action: .share,
            origins: ["https://apps.example.com"],
            purposeId: "share-report",
            purpose: "Share the selected report",
            scope: .once
        )
    }

    private func manifest(purpose: String = "Share the selected report") -> HTMLAppPolicyManifest {
        HTMLAppPolicyManifest(
            schemaVersion: "1",
            appId: "com.example.actions",
            name: "Actions",
            startURL: "https://apps.example.com/actions/index.html",
            allowedOrigins: ["https://apps.example.com"],
            capabilities: [],
            capabilitiesV2: [
                HTMLAppPolicyManifest.CapabilityDeclaration(
                    action: .share,
                    origins: ["https://apps.example.com"],
                    purposeId: "share-report",
                    purpose: purpose,
                    scope: .once
                )
            ],
            routes: ["/actions/index.html"],
            cache: .init(strategy: .networkOnly, version: "1", persistent: false),
            signature: nil
        )
    }

    private func makeService(dataDir: String) -> HTMLAppGatewayService {
        HTMLAppGatewayService(
            dataDir: dataDir,
            gatewayID: "test-gateway",
            gatewayName: "Test Gateway",
            publicBaseURL: "https://gateway.example.com",
            keyID: "test-key",
            privateKeyValue: base64URL(rawPrivateKey)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("drel-capabilities-v2-\(UUID().uuidString)", isDirectory: true)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
