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

    // MARK: - Category Expenses Cache (per-filter)

    private var categoryExpensesCache: [String: [String: CategoryExpense]] = [:]
    private var cacheAccessOrder: [String] = []
    private let maxCacheSize = 10

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

    /// REFACTORED 2026-02-02: Changed to LRU cache to prevent memory leaks
    /// Capacity: 10,000 entries (reasonable for ~3 years of daily transactions)
    private lazy var parsedDatesCache = LRUCache<String, Date>(capacity: 10_000)

    // MARK: - Index Manager

    let indexManager = TransactionIndexManager()

    // MARK: - Invalidation

    /// Invalidate all caches at once
    func invalidateAll() {
        summaryCacheInvalidated = true
        invalidateCategoryExpenses()
        categoryListsCacheInvalidated = true
        balanceCacheInvalidated = true
        accountsCacheInvalidated = true
        subcategoryIndexInvalidated = true
        parsedDatesCache.removeAll()
        indexManager.invalidate()
    }

    /// Invalidate only the accounts lookup cache
    func invalidateAccounts() {
        accountsCacheInvalidated = true
    }

    // MARK: - Category Expenses Cache Methods

    /// Get cached category expenses for specific time filter
    func getCachedCategoryExpenses(for filter: TimeFilter) -> [String: CategoryExpense]? {
        let key = makeCacheKey(filter)

        // Update access order for LRU
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
            cacheAccessOrder.append(key)
        }

        #if DEBUG
        if let cached = categoryExpensesCache[key] {
            print("✅ CategoryExpenses cache HIT for filter: \(filter.displayName)")
            return cached
        } else {
            print("❌ CategoryExpenses cache MISS for filter: \(filter.displayName)")
            return nil
        }
        #else
        return categoryExpensesCache[key]
        #endif
    }

    /// Set cached category expenses for specific time filter
    func setCachedCategoryExpenses(_ expenses: [String: CategoryExpense], for filter: TimeFilter) {
        let key = makeCacheKey(filter)

        // Remove old entry if exists
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
        }

        // Add to end (most recent)
        cacheAccessOrder.append(key)
        categoryExpensesCache[key] = expenses

        // Evict oldest if over limit
        if cacheAccessOrder.count > maxCacheSize {
            let oldestKey = cacheAccessOrder.removeFirst()
            categoryExpensesCache.removeValue(forKey: oldestKey)
            #if DEBUG
            print("🗑️ CategoryExpenses cache evicted oldest entry (LRU)")
            #endif
        }

        #if DEBUG
        print("💾 CategoryExpenses cached for filter: \(filter.displayName) (cache size: \(cacheAccessOrder.count)/\(maxCacheSize))")
        #endif
    }

    /// Invalidate all category expenses caches
    func invalidateCategoryExpenses() {
        categoryExpensesCache.removeAll()
        cacheAccessOrder.removeAll()
        #if DEBUG
        print("🧹 CategoryExpenses cache cleared")
        print("   Call stack:")
        Thread.callStackSymbols.prefix(5).forEach { print("   \($0)") }
        #endif
    }

    /// Generate unique cache key for time filter
    private func makeCacheKey(_ filter: TimeFilter) -> String {
        let range = filter.dateRange()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        let start = formatter.string(from: range.start)
        let end = formatter.string(from: range.end)

        return "\(filter.preset.rawValue)_\(start)_\(end)"
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
    /// REFACTORED 2026-02-02: Now uses LRU cache with automatic eviction
    func getParsedDate(for dateString: String) -> Date? {
        // Try cache first
        if let cached = parsedDatesCache.get(dateString) {
            return cached
        }

        // Parse and cache
        if let parsed = DateFormatters.dateFormatter.date(from: dateString) {
            parsedDatesCache.set(dateString, value: parsed)
            return parsed
        }

        return nil
    }

    #if DEBUG
    /// Get cache statistics for monitoring
    var parsedDatesCacheStats: String {
        parsedDatesCache.debugDescription
    }
    #endif
}
