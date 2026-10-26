//
//  GatewayAutoBindTests.swift
//  DrelTests
//
//  一码双绑的核心契约：自建推送配对成功后，App 拉取同源
//  /api/v1/gateway 描述符并入库（不抢活动网关）。这里锁定
//  「真实描述符 JSON → HTMLAppGatewayConfiguration 解码 → 注册表保存」
//  这段核心链路。
//

import XCTest
import WebBridgeKit
@testable import Drel

final class GatewayAutoBindTests: XCTestCase {

    /// relay.shanbox 线上描述符的逐字节形状（2026-10-24 curl 实录，密钥为公开值）。
    private let liveDescriptor = """
    {
      "baseURL": "https://relay.shanbox.19930810.xyz:8443",
      "healthPath": "/health",
      "id": "relay-shanbox",
      "manifestPath": "/api/v1/html-apps",
      "name": "Drel Self-hosted Gateway",
      "publicKey": "8UxhqhPZfmw61fWYj8PELp4MgTk5GBDnBexT85KLTZM",
      "publicKeyID": "gw-relay-20261023"
    }
    """

    func testLiveDescriptorDecodesIntoGatewayConfiguration() throws {
        let configuration = try JSONDecoder().decode(
            HTMLAppGatewayConfiguration.self,
            from: Data(liveDescriptor.utf8)
        )
        XCTAssertEqual(configuration.id, "relay-shanbox")
        XCTAssertEqual(configuration.baseURL, "https://relay.shanbox.19930810.xyz:8443")
        XCTAssertEqual(configuration.manifestPath, "/api/v1/html-apps")
        XCTAssertEqual(configuration.publicKeyID, "gw-relay-20261023")
        XCTAssertEqual(configuration.publicKey, "8UxhqhPZfmw61fWYj8PELp4MgTk5GBDnBexT85KLTZM")
    }

    func testAutoBindSavesWithoutActivating() throws {
        let configuration = try JSONDecoder().decode(
            HTMLAppGatewayConfiguration.self,
            from: Data(liveDescriptor.utf8)
        )
        let registry = HTMLAppGatewayRegistry(officialGateway: DrelGatewayConfiguration.official)

        // 幂等：先清掉同名（若此前跑过）
        try? registry.remove(id: configuration.id)

        try registry.save(configuration, activate: false)

        let saved = registry.allGateways().first { $0.id == configuration.id }
        XCTAssertNotNil(saved, "自动绑定后网关必须出现在注册表里")
        XCTAssertNotEqual(
            registry.activeGateway()?.id,
            configuration.id,
            "自动绑定只入库，不得抢走活动网关（首页应用目录不应被切到自建空清单）"
        )

        // 清理，不污染其他测试
        try? registry.remove(id: configuration.id)
    }
}
