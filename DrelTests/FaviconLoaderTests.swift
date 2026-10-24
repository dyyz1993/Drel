//
//  FaviconLoaderTests.swift
//  DrelTests
//

import XCTest
@testable import Drel

/// URLProtocol 桩：拦截 FaviconLoader 的网络请求并回报预设响应。
final class FaviconURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var requestCount = 0
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        let (status, data) = Self.handler?(request) ?? (404, Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/x-icon"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class FaviconLoaderTests: XCTestCase {

    private var loader: FaviconLoader!
    private var cache: IconCacheService!

    // 1×1 PNG 的字节序列（UIImage 可解码）
    private let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FaviconURLProtocolStub.self]
        cache = IconCacheService(policy: .init(byteBudget: 64 * 1024))
        loader = FaviconLoader(
            cache: cache,
            session: URLSession(configuration: config)
        )
        FaviconURLProtocolStub.handler = nil
        FaviconURLProtocolStub.requestCount = 0
        FaviconURLProtocolStub.lastRequest = nil
    }

    func testCacheHitSkipsNetwork() async {
        let url = URL(string: "https://example.com/page")!
        await cache.store(tinyPNG, forKey: FaviconLoader.cacheKey(for: url))

        let data = await loader.loadIcon(forPageURL: url)

        XCTAssertEqual(data, tinyPNG)
        XCTAssertEqual(FaviconURLProtocolStub.requestCount, 0, "缓存命中不得触发网络")
    }

    func testCacheMissFallsBackToNetworkAndStoresResult() async {
        FaviconURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.host, "example.com")
            XCTAssertEqual(request.url?.path, "/favicon.ico")
            return (200, self.tinyPNG)
        }
        let url = URL(string: "https://example.com/page")!

        let data = await loader.loadIcon(forPageURL: url)

        XCTAssertEqual(data, tinyPNG)
        XCTAssertEqual(FaviconURLProtocolStub.requestCount, 1)
        let cached = await cache.cachedData(forKey: FaviconLoader.cacheKey(for: url))
        XCTAssertEqual(cached, tinyPNG, "网络结果必须写回缓存")
    }

    func testSecondLoadAfterNetworkFetchHitsCacheNotNetwork() async {
        FaviconURLProtocolStub.handler = { _ in (200, self.tinyPNG) }
        let url = URL(string: "https://example.com/page")!

        _ = await loader.loadIcon(forPageURL: url)
        _ = await loader.loadIcon(forPageURL: url)

        XCTAssertEqual(FaviconURLProtocolStub.requestCount, 1, "第二次加载必须命中缓存")
    }

    func testUndecodablePayloadIsNotCached() async {
        FaviconURLProtocolStub.handler = { _ in (200, Data("not an image".utf8)) }
        let url = URL(string: "https://example.com/page")!

        let data = await loader.loadIcon(forPageURL: url)

        XCTAssertNil(data)
        let cached = await cache.cachedData(forKey: FaviconLoader.cacheKey(for: url))
        XCTAssertNil(cached, "解码失败的数据不得污染缓存")
    }

    func testHTTPErrorReturnsNil() async {
        FaviconURLProtocolStub.handler = { _ in (404, Data()) }
        let url = URL(string: "https://missing.example/page")!

        let data = await loader.loadIcon(forPageURL: url)

        XCTAssertNil(data)
    }

    func testConcurrentLoadsForSameHostSingleFlightTheNetwork() async {
        FaviconURLProtocolStub.handler = { _ in
            // 人为放大窗口，让并发请求可能同时落到网络
            Thread.sleep(forTimeInterval: 0.15)
            return (200, self.tinyPNG)
        }
        let url = URL(string: "https://example.com/a")!

        async let first = loader.loadIcon(forPageURL: url)
        async let second = loader.loadIcon(forPageURL: url)
        async let third = loader.loadIcon(forPageURL: url)
        _ = await (first, second, third)

        XCTAssertEqual(FaviconURLProtocolStub.requestCount, 1,
                       "同 host 并发加载必须合并为一次网络请求")
    }
}
