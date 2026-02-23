//
//  DataRepositoryProtocol.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Protocol defining data persistence operations for all entities

import Foundation

/// Protocol for data repository operations
/// Provides abstraction layer for data persistence
/// Sendable conformance allows capturing `any DataRepositoryProtocol` in Task.detached
/// (all concrete implementations use CoreDataStack which is @unchecked Sendable).
/// @preconcurrency suppresses actor-isolation inference warnings on conformers whose
/// methods have no explicit isolation annotation (e.g., CoreDataRepository).
@preconcurrency protocol DataRepositoryProtocol: Sendable {
    // MARK: - Transactions
    
    /// Load transactions with optional date range filter
    /// - Parameter dateRange: Optional date range to filter transactions. If nil, loads all transactions
    /// - Returns: Array of transactions matching the filter
    func loadTransactions(dateRange: DateInterval?) -> [Transaction]
    
    func saveTransactions(_ transactions: [Transaction])
    func deleteTransactionImmediately(id: String)

    /// Insert a single new transaction into CoreData. O(1) — does NOT fetch existing records.
    /// Use for .added events in TransactionStore.apply(). Prerequisite: transaction.id must be non-empty.
    func insertTransaction(_ transaction: Transaction)

    /// Update fields of a single existing transaction by ID. O(1) — fetches by PK only.
    /// Use for .updated events in TransactionStore.apply().
    func updateTransactionFields(_ transaction: Transaction)

    /// Batch-insert multiple new transactions using NSBatchInsertRequest. O(N) but fast.
    /// Bypasses NSManagedObject lifecycle — ideal for CSV import of 1k+ records.
    /// Note: Does NOT set CoreData relationships (account/recurringSeries).
    /// accountId/targetAccountId String columns are used as fallbacks by toTransaction().
    func batchInsertTransactions(_ transactions: [Transaction])

    // MARK: - Accounts
    func loadAccounts() -> [Account]
    func saveAccounts(_ accounts: [Account])
    func updateAccountBalance(accountId: String, balance: Double)
    func updateAccountBalances(_ balances: [String: Double])

    // MARK: - Categories
    func loadCategories() -> [CustomCategory]
    func saveCategories(_ categories: [CustomCategory])
    
    // MARK: - Category Rules
    func loadCategoryRules() -> [CategoryRule]
    func saveCategoryRules(_ rules: [CategoryRule])
    
    // MARK: - Recurring Series
    func loadRecurringSeries() -> [RecurringSeries]
    func saveRecurringSeries(_ series: [RecurringSeries])
    
    // MARK: - Recurring Occurrences
    func loadRecurringOccurrences() -> [RecurringOccurrence]
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])
    
    // MARK: - Subcategories
    func loadSubcategories() -> [Subcategory]
    func saveSubcategories(_ subcategories: [Subcategory])
    
    // MARK: - Category-Subcategory Links
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink]
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink])
    
    // MARK: - Transaction-Subcategory Links
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink]
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink])
    
    // MARK: - Clear All Data
    func clearAllData()
}
