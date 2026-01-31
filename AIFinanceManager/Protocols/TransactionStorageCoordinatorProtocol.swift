//
//  TransactionStorageCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Protocol defining storage operations for transactions and related data
/// Follows Single Responsibility Principle - handles only persistence operations
@MainActor
protocol TransactionStorageCoordinatorProtocol {
    /// Load all data asynchronously
    func loadFromStorage() async

    /// Load older transactions beyond initial display range
    func loadOlderTransactions()

    /// Save all data to storage asynchronously
    func saveToStorage()

    /// Save all data to storage synchronously (for CSV import)
    func saveToStorageSync()

    /// Debounced save to prevent excessive I/O
    func saveToStorageDebounced()
}

/// Delegate protocol for TransactionStorageCoordinator to access ViewModel state
@MainActor
protocol TransactionStorageDelegate: AnyObject {
    // State access
    var allTransactions: [Transaction] { get set }
    var displayTransactions: [Transaction] { get set }
    var hasOlderTransactions: Bool { get set }
    var categoryRules: [CategoryRule] { get set }
    var accounts: [Account] { get set }
    var customCategories: [CustomCategory] { get set }
    var recurringSeries: [RecurringSeries] { get set }
    var recurringOccurrences: [RecurringOccurrence] { get set }
    var subcategories: [Subcategory] { get set }
    var categorySubcategoryLinks: [CategorySubcategoryLink] { get set }
    var transactionSubcategoryLinks: [TransactionSubcategoryLink] { get set }
    var initialAccountBalances: [String: Double] { get set }
    var displayMonthsRange: Int { get }

    // Dependencies
    var repository: DataRepositoryProtocol { get }
    var accountBalanceService: AccountBalanceServiceProtocol { get }
    var cacheManager: TransactionCacheManager { get }

    // Coordination methods
    func invalidateCaches()
    func rebuildIndexes()
    func precomputeCurrencyConversions()
    func calculateTransactionsBalance(for accountId: String) -> Double
}
