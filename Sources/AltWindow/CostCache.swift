import Foundation

/// Deterministic LRU: an explicit byte budget, unlike NSCache's advisory limits.
struct CostCache<Value> {
    private struct Entry {
        let value: Value
        let cost: Int
        let createdAt: TimeInterval
        var access: UInt64
    }
    let byteLimit: Int
    let countLimit: Int
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var totalCost = 0
    var count: Int { entries.count }
    var values: [String: Value] { entries.mapValues(\.value) }

    mutating func insert(_ value: Value, for key: String, cost: Int, now: TimeInterval) {
        remove(key)
        guard cost >= 0, cost <= byteLimit, countLimit > 0 else { return }
        while !entries.isEmpty && (totalCost + cost > byteLimit || entries.count >= countLimit) {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            remove(oldest)
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, createdAt: now, access: clock)
        totalCost += cost
    }

    mutating func value(for key: String, now: TimeInterval, maxAge: TimeInterval) -> Value? {
        guard var entry = entries[key], now - entry.createdAt < maxAge else { remove(key); return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.value
    }

    func isFresh(_ key: String, now: TimeInterval, maxAge: TimeInterval) -> Bool {
        entries[key].map { now - $0.createdAt < maxAge } ?? false
    }

    mutating func retain(keys: Set<String>) {
        for key in Array(entries.keys) where !keys.contains(key) { remove(key) }
    }
    mutating func remove(_ key: String) {
        if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
    }
    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
        totalCost = 0
    }
}
