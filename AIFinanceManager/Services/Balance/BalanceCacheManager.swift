//
//  BalanceCacheManager.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 3
//
//  LRU cache for balance calculations
//  Auto-invalidation and incremental updates
//

import Foundation

// MARK: - Balance Cache Manager

/// LRU cache manager for balance calculations
/// Uses existing LRUCache<Key, Value> infrastructure
@MainActor
final class BalanceCacheManager {

    // MARK: - Cache Stores

    /// LRU cache for calculated balances
    private let balanceCache: LRUCache<String, Double>

    /// LRU cache for balance calculation metadata
    private let metadataCache: LRUCache<String, BalanceMetadata>

    /// Cache for affected accounts by transaction
    private var affectedAccountsCache: [String: Set<String>] = [:]

    // MARK: - Configuration

    private let balanceCacheCapacity: Int = 1000
    private let metadataCacheCapacity: Int = 500

    // MARK: - Statistics

    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var invalidations: Int = 0

    // MARK: - Initialization

    init() {
        self.balanceCache = LRUCache<String, Double>(capacity: balanceCacheCapacity)
        self.metadataCache = LRUCache<String, BalanceMetadata>(capacity: metadataCacheCapacity)

        #if DEBUG
        print("✅ BalanceCacheManager initialized (capacity: \(balanceCacheCapacity))")
        #endif
    }

    // MARK: - Cache Operations

    /// Get cached balance for account
    /// - Parameter accountId: Account ID
    /// - Returns: Cached balance if available
    func getBalance(for accountId: String) -> Double? {
        if let balance = balanceCache.get(accountId) {
            cacheHits += 1
            return balance
        }

        cacheMisses += 1
        return nil
    }

    /// Set balance in cache
    /// - Parameters:
    ///   - balance: Balance value
    ///   - accountId: Account ID
    func setBalance(_ balance: Double, for accountId: String) {
        balanceCache.set(accountId, value: balance)

        // Update metadata
        let metadata = BalanceMetadata(
            lastUpdated: Date(),
            transactionCount: metadataCache.get(accountId)?.transactionCount ?? 0,
            calculationMode: metadataCache.get(accountId)?.calculationMode ?? .fromInitialBalance
        )
        metadataCache.set(accountId, value: metadata)

        #if DEBUG
        print("💾 Cached balance for \(accountId): \(balance)")
        #endif
    }

    /// Update multiple balances in cache
    /// - Parameter balances: Dictionary of account ID to balance
    func setBalances(_ balances: [String: Double]) {
        for (accountId, balance) in balances {
            setBalance(balance, for: accountId)
        }

        #if DEBUG
        print("💾 Cached \(balances.count) balances")
        #endif
    }

    /// Invalidate balance for specific account
    /// - Parameter accountId: Account ID
    func invalidate(accountId: String) {
        balanceCache.remove(accountId)
        metadataCache.remove(accountId)
        invalidations += 1

        #if DEBUG
        print("🗑️ Invalidated cache for account: \(accountId)")
        #endif
    }

    /// Invalidate balances for multiple accounts
    /// - Parameter accountIds: Set of account IDs
    func invalidate(accountIds: Set<String>) {
        for accountId in accountIds {
            balanceCache.remove(accountId)
            metadataCache.remove(accountId)
        }

        invalidations += accountIds.count

        #if DEBUG
        print("🗑️ Invalidated cache for \(accountIds.count) accounts")
        #endif
    }

    /// Invalidate all cached balances
    func invalidateAll() {
        let count = balanceCache.count
        balanceCache.removeAll()
        metadataCache.removeAll()
        affectedAccountsCache.removeAll()
        invalidations += count

        #if DEBUG
        print("🗑️ Invalidated all caches (\(count) entries)")
        #endif
    }

    // MARK: - Metadata Operations

    /// Get metadata for account
    /// - Parameter accountId: Account ID
    /// - Returns: Balance metadata if cached
    func getMetadata(for accountId: String) -> BalanceMetadata? {
        return metadataCache.get(accountId)
    }

    /// Update metadata for account
    /// - Parameters:
    ///   - metadata: Balance metadata
    ///   - accountId: Account ID
    func setMetadata(_ metadata: BalanceMetadata, for accountId: String) {
        metadataCache.set(accountId, value: metadata)
    }

    // MARK: - Affected Accounts Tracking

    /// Track which accounts are affected by a transaction
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - affectedAccounts: Set of affected account IDs
    func trackAffectedAccounts(for transaction: Transaction, affectedAccounts: Set<String>) {
        affectedAccountsCache[transaction.id] = affectedAccounts
    }

    /// Get affected accounts for a transaction
    /// - Parameter transactionId: Transaction ID
    /// - Returns: Set of affected account IDs
    func getAffectedAccounts(for transactionId: String) -> Set<String>? {
        return affectedAccountsCache[transactionId]
    }

    /// Remove affected accounts tracking for transaction
    /// - Parameter transactionId: Transaction ID
    func removeAffectedAccounts(for transactionId: String) {
        affectedAccountsCache.removeValue(forKey: transactionId)
    }

    // MARK: - Smart Invalidation

    /// Invalidate cache based on transaction changes
    /// Only invalidates affected accounts for better performance
    /// - Parameter transaction: The transaction that changed
    func smartInvalidate(for transaction: Transaction) {
        var accountsToInvalidate: Set<String> = []

        switch transaction.type {
        case .income, .expense:
            if let accountId = transaction.accountId {
                accountsToInvalidate.insert(accountId)
            }

        case .internalTransfer:
            if let sourceId = transaction.accountId {
                accountsToInvalidate.insert(sourceId)
            }
            if let targetId = transaction.targetAccountId {
                accountsToInvalidate.insert(targetId)
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            if let accountId = transaction.accountId {
                accountsToInvalidate.insert(accountId)
            }
        }

        invalidate(accountIds: accountsToInvalidate)

        #if DEBUG
        print("🎯 Smart invalidation: \(accountsToInvalidate.count) accounts affected")
        #endif
    }

    /// Invalidate cache for batch of transactions
    /// Collects all affected accounts and invalidates once
    /// - Parameter transactions: Array of transactions
    func smartInvalidate(for transactions: [Transaction]) {
        var accountsToInvalidate: Set<String> = []

        for transaction in transactions {
            switch transaction.type {
            case .income, .expense:
                if let accountId = transaction.accountId {
                    accountsToInvalidate.insert(accountId)
                }

            case .internalTransfer:
                if let sourceId = transaction.accountId {
                    accountsToInvalidate.insert(sourceId)
                }
                if let targetId = transaction.targetAccountId {
                    accountsToInvalidate.insert(targetId)
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                if let accountId = transaction.accountId {
                    accountsToInvalidate.insert(accountId)
                }
            }
        }

        invalidate(accountIds: accountsToInvalidate)

        #if DEBUG
        print("🎯 Batch smart invalidation: \(accountsToInvalidate.count) accounts affected from \(transactions.count) transactions")
        #endif
    }

    // MARK: - Statistics

    /// Get cache statistics
    func getStatistics() -> CacheStatistics {
        return CacheStatistics(
            totalEntries: balanceCache.count,
            capacity: balanceCacheCapacity,
            hits: cacheHits,
            misses: cacheMisses,
            invalidations: invalidations,
            hitRate: cacheHits > 0 ? Double(cacheHits) / Double(cacheHits + cacheMisses) : 0.0
        )
    }

    /// Reset statistics
    func resetStatistics() {
        cacheHits = 0
        cacheMisses = 0
        invalidations = 0
    }

    /// Check if cache should be used based on hit rate
    /// Returns false if hit rate is too low (<50%)
    func shouldUseCache() -> Bool {
        let stats = getStatistics()
        return stats.hitRate >= 0.5 || (cacheHits + cacheMisses) < 100
    }
}

// MARK: - Balance Metadata

/// Metadata about a cached balance calculation
struct BalanceMetadata {
    let lastUpdated: Date
    let transactionCount: Int
    let calculationMode: BalanceMode // MIGRATED: Using BalanceMode from BalanceStore

    var age: TimeInterval {
        return Date().timeIntervalSince(lastUpdated)
    }

    var isStale: Bool {
        return age > 300 // 5 minutes
    }
}

// MARK: - Cache Statistics

struct CacheStatistics {
    let totalEntries: Int
    let capacity: Int
    let hits: Int
    let misses: Int
    let invalidations: Int
    let hitRate: Double

    var utilizationPercent: Double {
        return Double(totalEntries) / Double(capacity) * 100.0
    }
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceCacheManager {
    /// Print cache statistics
    func debugPrintStatistics() {
        let stats = getStatistics()
        print("====== BalanceCacheManager Statistics ======")
        print("Entries: \(stats.totalEntries) / \(stats.capacity) (\(Int(stats.utilizationPercent))%)")
        print("Hits: \(stats.hits), Misses: \(stats.misses)")
        print("Hit Rate: \(Int(stats.hitRate * 100))%")
        print("Invalidations: \(stats.invalidations)")
        print("=============================================")
    }

    /// Get all cached account IDs
    func getCachedAccountIds() -> [String] {
        return Array(balanceCache.map { $0.key })
    }
}
#endif
