//
//  IconCacheServiceTests.swift
//  DrelTests
//

import XCTest
@testable import Drel

/// 固定预算 LRU 图标缓存的算法契约：
/// 淘汰按「最近使用」时间序（命中刷新新鲜度）、预算硬约束、覆盖更新计费。
final class IconCacheServiceTests: XCTestCase {

    private func makeCache(budget: Int) -> IconCacheService {
        IconCacheService(policy: .init(byteBudget: budget))
    }

    func testStoreAndHitRoundTrip() async {
        let cache = makeCache(budget: 100)
        await cache.store(Data([1, 2, 3]), forKey: "a")
        let hit = await cache.cachedData(forKey: "a")
        XCTAssertEqual(hit, Data([1, 2, 3]))
    }

    func testMissReturnsNil() async {
        let cache = makeCache(budget: 100)
        let miss = await cache.cachedData(forKey: "missing")
        XCTAssertNil(miss)
    }

    func testOldestEntryIsEvictedWhenBudgetExceeded() async {
        let cache = makeCache(budget: 6)
        await cache.store(Data([1, 1, 1]), forKey: "first")   // 3 bytes
        await cache.store(Data([2, 2, 2]), forKey: "second")  // 3 bytes → 满预算
        await cache.store(Data([3, 3, 3]), forKey: "third")   // 超预算 → 淘汰最旧
        let first = await cache.cachedData(forKey: "first")
        XCTAssertNil(first, "最旧条目必须先被淘汰")
        let second = await cache.cachedData(forKey: "second")
        XCTAssertNotNil(second)
        let third = await cache.cachedData(forKey: "third")
        XCTAssertNotNil(third)
        let bytes = await cache.usedBytes
        XCTAssertLessThanOrEqual(bytes, 6)
    }

    func testHitRefreshesRecencySoRecentlyReadEntrySurvives() async {
        let cache = makeCache(budget: 6)
        await cache.store(Data([1, 1, 1]), forKey: "first")
        await cache.store(Data([2, 2, 2]), forKey: "second")
        // 读 first 刷新它的新鲜度，使 second 成为最旧
        _ = await cache.cachedData(forKey: "first")
        await cache.store(Data([3, 3, 3]), forKey: "third")
        let first = await cache.cachedData(forKey: "first")
        XCTAssertNotNil(first, "刚被命中的条目不该被淘汰")
        let second = await cache.cachedData(forKey: "second")
        XCTAssertNil(second, "最久未使用的条目应被淘汰")
    }

    func testOverwriteReplacesCostInsteadOfDoubling() async {
        let cache = makeCache(budget: 6)
        await cache.store(Data([1, 1, 1]), forKey: "a")
        await cache.store(Data(repeating: 9, count: 5), forKey: "a") // 覆盖：5 字节
        let bytes = await cache.usedBytes
        XCTAssertEqual(bytes, 5, "覆盖同一 key 必须替换计费而不是累加")
        let count = await cache.entryCount
        XCTAssertEqual(count, 1)
    }

    func testEmptyDataIsRejected() async {
        let cache = makeCache(budget: 10)
        await cache.store(Data(), forKey: "empty")
        let count = await cache.entryCount
        XCTAssertEqual(count, 0, "空数据不占预算、不入缓存")
    }

    func testOversizedSingleEntryIsKeptAlone() async {
        let cache = makeCache(budget: 4)
        await cache.store(Data([1, 1]), forKey: "small")
        await cache.store(Data(repeating: 7, count: 100), forKey: "huge")
        let huge = await cache.cachedData(forKey: "huge")
        XCTAssertNotNil(huge, "超预算单条保底保留，避免缓存永远打空")
        let small = await cache.cachedData(forKey: "small")
        XCTAssertNil(small)
    }

    func testRemoveAllClearsEverything() async {
        let cache = makeCache(budget: 100)
        await cache.store(Data([1]), forKey: "a")
        await cache.store(Data([2]), forKey: "b")
        await cache.removeAll()
        let count = await cache.entryCount
        XCTAssertEqual(count, 0)
        let bytes = await cache.usedBytes
        XCTAssertEqual(bytes, 0)
    }

    func testConcurrentStoreAndReadStayWithinBudget() async {
        let cache = makeCache(budget: 50)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    await cache.store(Data(repeating: UInt8(i % 255), count: 4), forKey: "k\(i)")
                    _ = await cache.cachedData(forKey: "k\(i % 50)")
                }
            }
        }
        let bytes = await cache.usedBytes
        XCTAssertLessThanOrEqual(bytes, 50, "并发读写后预算仍必须成立")
    }
}
