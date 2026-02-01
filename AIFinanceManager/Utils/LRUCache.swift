//
//  LRUCache.swift
//  AIFinanceManager
//
//  Generic Least Recently Used (LRU) cache implementation
//  Used for memory-efficient caching with automatic eviction
//

import Foundation

/// Generic LRU cache with automatic eviction of least recently used items
final class LRUCache<Key: Hashable, Value> {

    // MARK: - Node

    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    // MARK: - Properties

    /// Hash map for O(1) lookups
    private var cache: [Key: Node] = [:]

    /// Doubly-linked list for LRU ordering
    private var head: Node?
    private var tail: Node?

    /// Maximum capacity
    private let capacity: Int

    /// Current size
    var count: Int {
        cache.count
    }

    // MARK: - Initialization

    /// Initialize with capacity
    /// - Parameter capacity: Maximum number of items to cache
    init(capacity: Int) {
        self.capacity = Swift.max(1, capacity) // Ensure capacity >= 1
    }

    // MARK: - Public Methods

    /// Get value for key (marks as recently used)
    /// - Parameter key: Key to lookup
    /// - Returns: Value if exists, nil otherwise
    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else { return nil }

        // Move to front (most recently used)
        moveToFront(node)

        return node.value
    }

    /// Set value for key (evicts LRU if at capacity)
    /// - Parameters:
    ///   - key: Key to set
    ///   - value: Value to cache
    func set(_ key: Key, value: Value) {
        if let existingNode = cache[key] {
            // Update existing node
            existingNode.value = value
            moveToFront(existingNode)
        } else {
            // Create new node
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToFront(newNode)

            // Evict LRU if over capacity
            if cache.count > capacity {
                evictLRU()
            }
        }
    }

    /// Remove value for key
    /// - Parameter key: Key to remove
    func remove(_ key: Key) {
        guard let node = cache[key] else { return }

        removeNode(node)
        cache.removeValue(forKey: key)
    }

    /// Remove all cached values
    func removeAll() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    /// Get all keys (ordered by recency, most recent first)
    func allKeys() -> [Key] {
        var keys: [Key] = []
        var current = head

        while let node = current {
            keys.append(node.key)
            current = node.next
        }

        return keys
    }

    // MARK: - Private Methods

    /// Move node to front (mark as most recently used)
    private func moveToFront(_ node: Node) {
        guard node !== head else { return }

        // Remove from current position
        removeNode(node)

        // Add to front
        addToFront(node)
    }

    /// Add node to front of list
    private func addToFront(_ node: Node) {
        node.next = head
        node.prev = nil

        if let head = head {
            head.prev = node
        }

        head = node

        if tail == nil {
            tail = node
        }
    }

    /// Remove node from list
    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }

        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }

        node.prev = nil
        node.next = nil
    }

    /// Evict least recently used item (tail)
    private func evictLRU() {
        guard let lruNode = tail else { return }

        #if DEBUG
        print("🗑️ [LRUCache] Evicting LRU item (capacity: \(capacity))")
        #endif

        removeNode(lruNode)
        cache.removeValue(forKey: lruNode.key)
    }
}

// MARK: - Sequence Conformance

extension LRUCache: Sequence {
    func makeIterator() -> AnyIterator<(Key, Value)> {
        var current = head

        return AnyIterator {
            guard let node = current else { return nil }
            current = node.next
            return (node.key, node.value)
        }
    }
}
