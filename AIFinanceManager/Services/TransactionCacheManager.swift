//
//  TransactionCacheManager.swift
//  AIFinanceManager
//
//  Centralized cache management for transactions, summaries, and account lookups.
//

import Foundation

/// Управляет кэшами для:
/// - Summary (income/expense totals)
/// - Category expenses
/// - Account balance calculations
/// - O(1) account lookup by ID
/// - Transaction indexes (fast filtering)
@MainActor
class TransactionCacheManager {

    // MARK: - Summary Cache

    var cachedSummary: Summary?
    var summaryCacheInvalidated = true

    // MARK: - Category Expenses Cache

    var cachedCategoryExpenses: [String: CategoryExpense]?
    var categoryExpensesCacheInvalidated = true

    // MARK: - Account Balance Cache

    var cachedAccountBalances: [String: Double] = [:]
    var balanceCacheInvalidated = true
    var lastBalanceCalculationTransactionCount = 0

    // MARK: - Accounts Lookup Cache

    private var cachedAccountsById: [String: Account] = [:]
    private var accountsCacheInvalidated = true

    // MARK: - Index Manager

    let indexManager = TransactionIndexManager()

    // MARK: - Invalidation

    /// Invalidate all caches at once
    func invalidateAll() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
        balanceCacheInvalidated = true
        accountsCacheInvalidated = true
        indexManager.invalidate()
    }

    /// Invalidate only the accounts lookup cache
    func invalidateAccounts() {
        accountsCacheInvalidated = true
    }

    // MARK: - Account Lookup

    /// Returns cached dictionary of accounts by ID for O(1) lookup.
    /// Rebuilds only when accounts data changes.
    func getAccountsById(accounts: [Account]) -> [String: Account] {
        if accountsCacheInvalidated || cachedAccountsById.isEmpty {
            cachedAccountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            accountsCacheInvalidated = false
        }
        return cachedAccountsById
    }

    // MARK: - Index Management

    /// Rebuild transaction indexes for fast filtering
    func rebuildIndexes(transactions: [Transaction]) {
        indexManager.buildIndexes(transactions: transactions)
    }
}
