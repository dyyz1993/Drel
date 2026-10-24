//
//  IconCacheService.swift
//  Drel
//

import Foundation

/// 固定字节预算的图标缓存，按「最近使用」时间顺序淘汰（LRU）。
///
/// - 命中会刷新该条目的最近使用时间；插入同样视为一次使用。
/// - 超出预算时从最旧一端淘汰，直到预算内（单条超大时保底保留最新一条，
///   保证极端大图不会导致缓存永远为空）。
/// - actor 串行化所有访问，列表刷新、网络回填与单元测试可以并发竞争。
actor IconCacheService {

    struct Policy: Sendable {
        let byteBudget: Int
        /// 产品默认预算：8 MB，足够几百枚 64–128pt favicon。
        static let standard = Policy(byteBudget: 8 * 1024 * 1024)
    }

    private struct Entry {
        var data: Data
        var lastUsed: Date
    }

    private var byteBudget: Int
    private var entries: [String: Entry] = [:]
    private(set) var usedBytes = 0

    init(policy: Policy = .standard) {
        self.byteBudget = max(0, policy.byteBudget)
    }

    /// 缓存命中返回数据并刷新其新鲜度；未命中返回 nil。
    func cachedData(forKey key: String) -> Data? {
        guard var entry = entries[key] else { return nil }
        entry.lastUsed = Date()
        entries[key] = entry
        return entry.data
    }

    /// 写入并按预算淘汰。空数据直接忽略（无意义占位会污染预算）。
    func store(_ data: Data, forKey key: String) {
        guard !data.isEmpty else { return }
        if let existing = entries[key] {
            usedBytes -= existing.data.count
        }
        entries[key] = Entry(data: data, lastUsed: Date())
        usedBytes += data.count
        evictIfNeeded()
    }

    /// 便于测试与「清空图标缓存」类设置项。
    func removeAll() {
        entries.removeAll()
        usedBytes = 0
    }

    var entryCount: Int { entries.count }

    private func evictIfNeeded() {
        guard usedBytes > byteBudget else { return }
        while usedBytes > byteBudget, entries.count > 1 {
            guard let oldestKey = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key,
                  let oldest = entries[oldestKey] else { break }
            usedBytes -= oldest.data.count
            entries.removeValue(forKey: oldestKey)
        }
    }
}
