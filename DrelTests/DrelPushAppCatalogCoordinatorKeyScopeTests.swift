//
//  DrelPushAppCatalogCoordinatorKeyScopeTests.swift
//  DrelTests
//
//  私有清单按 Key 隔离的核心契约（FR-20261029-01）：官方网关的清单
//  拉取路径带上本机推送标识（?key=），且该路径必须通过 SDK 的网关
//  配置校验；自建网关与无标识场景不注入；Key 重生成后旧值不残留。
//

import XCTest
import WebBridgeKit
@testable import Drel

final class DrelPushAppCatalogCoordinatorKeyScopeTests: XCTestCase {

    private let identityKey = "com.webbridgekit.official-push.identity"
    private var savedIdentity: String?

    override func setUp() {
        super.setUp()
        savedIdentity = UserDefaults.standard.string(forKey: identityKey)
        UserDefaults.standard.set("simtestkey000001", forKey: identityKey)
    }

    override func tearDown() {
        if let savedIdentity {
            UserDefaults.standard.set(savedIdentity, forKey: identityKey)
        } else {
            UserDefaults.standard.removeObject(forKey: identityKey)
        }
        super.tearDown()
    }

    func testOfficialGatewayManifestPathGainsCurrentKeyScope() throws {
        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(
            DrelGatewayConfiguration.official
        )

        XCTAssertEqual(scoped.manifestPath, "/api/v1/html-apps?key=simtestkey000001")
        // 身份字段不随作用域变化：授权账本按 baseURL+信任锚匹配，不能因
        // 拉取路径带 Key 而被当成另一个网关。
        XCTAssertEqual(scoped.baseURL, DrelGatewayConfiguration.official.baseURL)
        XCTAssertEqual(scoped.id, DrelGatewayConfiguration.official.id)
        XCTAssertEqual(scoped.publicKeyID, DrelGatewayConfiguration.official.publicKeyID)
        XCTAssertEqual(scoped.publicKey, DrelGatewayConfiguration.official.publicKey)

        // SDK 必须接受带 query 的清单端点，否则协调器的按需刷新会在
        // 配置校验处整体失败。
        XCTAssertTrue(scoped.validate().isValid)
    }

    func testStaleScopeIsReplacedWithTheCurrentKey() throws {
        let stale = HTMLAppGatewayConfiguration(
            id: DrelGatewayConfiguration.official.id,
            name: DrelGatewayConfiguration.official.name,
            baseURL: DrelGatewayConfiguration.official.baseURL,
            healthPath: DrelGatewayConfiguration.official.healthPath,
            manifestPath: "/api/v1/html-apps?key=regenerated-old",
            publicKeyID: DrelGatewayConfiguration.official.publicKeyID,
            publicKey: DrelGatewayConfiguration.official.publicKey
        )

        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(stale)
        XCTAssertEqual(scoped.manifestPath, "/api/v1/html-apps?key=simtestkey000001")
    }

    func testAudioCapableClientAdvertisesSupportedAction() {
        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(
            DrelGatewayConfiguration.official, supportsAudioLevel: true
        )
        let items = URLComponents(string: scoped.manifestPath)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "key", value: "simtestkey000001")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "supportedActions", value: "audioLevel")))
        XCTAssertTrue(scoped.validate().isValid)
    }

    func testLegacyClientDoesNotAdvertiseUnsupportedAudio() {
        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(
            DrelGatewayConfiguration.official, supportsAudioLevel: false
        )
        XCTAssertEqual(scoped.manifestPath, "/api/v1/html-apps?key=simtestkey000001")
    }

    func testNonOfficialGatewayIsLeftUnchanged() throws {
        let selfHosted = HTMLAppGatewayConfiguration(
            name: "Self-hosted Gateway",
            baseURL: "https://relay.example.com",
            manifestPath: "/api/v1/html-apps",
            publicKeyID: "gw-relay-test",
            publicKey: "8UxhqhPZfmw61fWYj8PELp4MgTk5GBDnBexT85KLTZM"
        )

        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(selfHosted)
        XCTAssertEqual(scoped.manifestPath, "/api/v1/html-apps")
    }

    func testMissingIdentityLeavesGatewayUnchanged() throws {
        // 宿主 App 启动即创建官方身份（UserDefaults 缓存 + Keychain 双写），
        // 两处都清掉才能稳定走到「无标识」分支。
        UserDefaults.standard.removeObject(forKey: identityKey)
        try? KeychainPushDeviceIdentityStorage().delete()

        let scoped = DrelPushAppCatalogCoordinator.deviceKeyScopedGateway(
            DrelGatewayConfiguration.official
        )
        XCTAssertEqual(scoped.manifestPath, DrelGatewayConfiguration.official.manifestPath)
    }
}
