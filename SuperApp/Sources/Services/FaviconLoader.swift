//
//  FaviconLoader.swift
//  Drel
//

import Foundation
import UIKit

/// 图标加载门面：缓存优先，未命中走网络，结果写回 LRU。
///
/// - 键是页面的 host（小写），同一站点不同页面共享一枚图标。
/// - 同一 host 的并发请求合并为一次网络往返（single-flight），收藏夹
///   批量回填时不会对同一站点打出请求风暴。
/// - 网络源依次尝试：`https://<host>/favicon.ico`；两跳都失败返回 nil，
///   由调用方继续展示首字母兜底。
final class FaviconLoader {
    static let shared = FaviconLoader()

    private let cache: IconCacheService
    private let session: URLSession
    private var inflight: [String: Task<Data?, Never>] = [:]
    private let lock = NSLock()

    init(
        cache: IconCacheService = IconCacheService(),
        session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()
    ) {
        self.cache = cache
        self.session = session
    }

    /// 仅读缓存（不触发网络）。列表首帧用它做零成本渲染。
    func cachedIcon(forPageURL url: URL) async -> Data? {
        await cache.cachedData(forKey: Self.cacheKey(for: url))
    }

    /// 缓存优先的完整加载路径。
    func loadIcon(forPageURL url: URL) async -> Data? {
        let key = Self.cacheKey(for: url)
        if let hit = await cache.cachedData(forKey: key) {
            return hit
        }
        return await startOrJoinInflight(key: key, url: url)
    }

    private func startOrJoinInflight(key: String, url: URL) async -> Data? {
        lock.lock()
        if let running = inflight[key] {
            lock.unlock()
            return await running.value
        }
        let host = url.host.map { $0.lowercased() } ?? url.absoluteString
        let task = Task<Data?, Never> { [session] in
            let data = await Self.fetchFavicon(host: host, session: session)
            guard let data, !data.isEmpty else { return nil }
            await self.cache.store(data, forKey: key)
            return data
        }
        inflight[key] = task
        lock.unlock()

        let result = await task.value
        lock.lock()
        inflight.removeValue(forKey: key)
        lock.unlock()
        return result
    }

    static func cacheKey(for url: URL) -> String {
        (url.host ?? url.absoluteString).lowercased()
    }

    /// 拉取 favicon 字节；只接受能被 UIImage 解码的数据。
    static func fetchFavicon(host: String, session: URLSession) async -> Data? {
        guard let faviconURL = URL(string: "https://\(host)/favicon.ico") else { return nil }
        var request = URLRequest(url: faviconURL)
        request.setValue("Mozilla/5.0 (Drel app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              UIImage(data: data) != nil else {
            return nil
        }
        return data
    }
}
