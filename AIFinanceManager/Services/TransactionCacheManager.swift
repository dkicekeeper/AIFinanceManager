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

    // MARK: - Category Lists Cache

    var cachedUniqueCategories: [String]?
    var cachedExpenseCategories: [String]?
    var cachedIncomeCategories: [String]?
    var categoryListsCacheInvalidated = true

    // MARK: - Account Balance Cache

    var cachedAccountBalances: [String: Double] = [:]
    var balanceCacheInvalidated = true
    var lastBalanceCalculationTransactionCount = 0

    // MARK: - Accounts Lookup Cache

    private var cachedAccountsById: [String: Account] = [:]
    private var accountsCacheInvalidated = true

    // MARK: - Subcategory Index

    private var transactionSubcategoryIndex: [String: Set<String>] = [:]
    private var subcategoryIndexInvalidated = true

    // MARK: - Parsed Dates Cache

    private var parsedDatesCache: [String: Date] = [:]

    // MARK: - Index Manager

    let indexManager = TransactionIndexManager()

    // MARK: - Invalidation

    /// Invalidate all caches at once
    func invalidateAll() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
        categoryListsCacheInvalidated = true
        balanceCacheInvalidated = true
        accountsCacheInvalidated = true
        subcategoryIndexInvalidated = true
        parsedDatesCache.removeAll(keepingCapacity: true)
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

    // MARK: - Subcategory Lookup

    /// Build subcategory lookup index for O(1) access
    func buildSubcategoryIndex(links: [TransactionSubcategoryLink]) {
        guard subcategoryIndexInvalidated else { return }

        transactionSubcategoryIndex.removeAll(keepingCapacity: true)
        transactionSubcategoryIndex.reserveCapacity(links.count)

        for link in links {
            transactionSubcategoryIndex[link.transactionId, default: []].insert(link.subcategoryId)
        }

        subcategoryIndexInvalidated = false
    }

    /// Get subcategory IDs for a transaction (O(1))
    func getSubcategoryIds(for transactionId: String) -> Set<String> {
        return transactionSubcategoryIndex[transactionId] ?? []
    }

    // MARK: - Date Parsing Cache

    /// Get parsed date from cache or parse and cache it (O(1) for cached dates)
    func getParsedDate(for dateString: String) -> Date? {
        if let cached = parsedDatesCache[dateString] {
            return cached
        }
        if let parsed = DateFormatters.dateFormatter.date(from: dateString) {
            parsedDatesCache[dateString] = parsed
            return parsed
        }
        return nil
    }
}
