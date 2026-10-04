import XCTest
@testable import AltWindow

final class CostCacheTests: XCTestCase {
    func testThousandsOfWindowPreviewsStayWithinBothBudgets() {
        var cache = CostCache<Int>(byteLimit: 8_388_608, countLimit: 24)
        for index in 0..<10_000 {
            cache.insert(index, for: "window-\(index)", cost: (index % 5 + 1) * 190_000, now: Double(index))
            XCTAssertLessThanOrEqual(cache.totalCost, cache.byteLimit)
            XCTAssertLessThanOrEqual(cache.count, cache.countLimit)
        }
        cache.removeAll()
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.count, 0)
    }
    func testRecentlyViewedPreviewSurvivesEviction() {
        var cache = CostCache<String>(byteLimit: 100, countLimit: 3)
        cache.insert("A", for: "a", cost: 40, now: 0)
        cache.insert("B", for: "b", cost: 40, now: 0)
        XCTAssertEqual(cache.value(for: "a", now: 1, maxAge: 15), "A")
        cache.insert("C", for: "c", cost: 40, now: 1)
        XCTAssertNil(cache.values["b"])
        XCTAssertEqual(cache.totalCost, 80)
    }
    func testExpiredAndClosedWindowsReleaseTheirBytes() {
        var cache = CostCache<Int>(byteLimit: 100, countLimit: 5)
        cache.insert(1, for: "a", cost: 20, now: 10)
        cache.insert(2, for: "b", cost: 30, now: 20)
        XCTAssertNil(cache.value(for: "a", now: 25, maxAge: 15))
        XCTAssertEqual(cache.totalCost, 30)
        cache.retain(keys: [])
        XCTAssertEqual(cache.totalCost, 0)
    }
    func testReplacingAndRejectingOversizedEntryDoesNotLeakAccounting() {
        var cache = CostCache<Int>(byteLimit: 100, countLimit: 2)
        cache.insert(1, for: "a", cost: 90, now: 0)
        cache.insert(2, for: "a", cost: 20, now: 1)
        XCTAssertEqual(cache.totalCost, 20)
        cache.insert(3, for: "a", cost: 101, now: 2)
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.count, 0)
    }
}
