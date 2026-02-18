//
//  InsightsCache.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  In-memory LRU cache with TTL for computed insights.
//
//  Design:
//  - Maximum `capacity` entries (default 20) to bound memory usage
//  - TTL (default 5 min) expiry — stale entries are lazily removed on read
//  - LRU eviction: the access-ordered array `lruKeys` tracks usage order;
//    the oldest entry is evicted when capacity is exceeded
//  - All operations are O(1) via dictionary + O(n) LRU scan (n ≤ 20, negligible)
//

import Foundation

@MainActor
final class InsightsCache {
    // MARK: - Types

    private struct CacheEntry {
        let insights: [Insight]
        let timestamp: Date
    }

    // MARK: - Properties

    private var cache: [String: CacheEntry] = [:]
    /// Insertion-order list; most-recently used key moves to the back.
    private var lruKeys: [String] = []
    private let ttl: TimeInterval
    private let capacity: Int

    // MARK: - Init

    init(ttl: TimeInterval = 300, capacity: Int = 20) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
    }

    // MARK: - Public API

    func get(key: String) -> [Insight]? {
        guard let entry = cache[key] else { return nil }

        // TTL check — lazy eviction on read
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            evict(key: key)
            return nil
        }

        // Promote to most-recently-used
        promote(key: key)
        return entry.insights
    }

    func set(key: String, insights: [Insight]) {
        if cache[key] != nil {
            // Overwrite existing — promote it
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            promote(key: key)
        } else {
            // New entry — evict LRU if at capacity
            if cache.count >= capacity, let oldest = lruKeys.first {
                evict(key: oldest)
            }
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            lruKeys.append(key)
        }
    }

    func invalidateAll() {
        cache.removeAll()
        lruKeys.removeAll()
    }

    func invalidate(category: InsightCategory) {
        let keysToRemove = cache.keys.filter { $0.contains(category.rawValue) }
        for key in keysToRemove { evict(key: key) }
    }

    // MARK: - Cache Key

    static func makeKey(timeFilter: TimeFilter, baseCurrency: String) -> String {
        "\(timeFilter.preset.rawValue)_\(baseCurrency)_\(timeFilter.startDate.timeIntervalSince1970)"
    }

    // MARK: - Private Helpers

    private func promote(key: String) {
        if let idx = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: idx)
            lruKeys.append(key)
        }
    }

    private func evict(key: String) {
        cache.removeValue(forKey: key)
        lruKeys.removeAll { $0 == key }
    }
}
