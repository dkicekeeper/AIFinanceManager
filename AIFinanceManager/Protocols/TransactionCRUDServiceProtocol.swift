//
//  TransactionCRUDServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Protocol defining CRUD operations for transactions
/// Follows Single Responsibility Principle - handles only Create, Read, Update, Delete operations
@MainActor
protocol TransactionCRUDServiceProtocol {
    /// Add a single transaction with automatic category matching and rule application
    /// - Parameter transaction: The transaction to add
    func addTransaction(_ transaction: Transaction)

    /// Add multiple transactions (optimized for bulk operations like CSV import)
    /// - Parameters:
    ///   - transactions: Array of transactions to add
    ///   - mode: Import mode - regular or CSV import (preserves account names)
    func addTransactions(_ transactions: [Transaction], mode: TransactionAddMode)

    /// Update an existing transaction
    /// - Parameter transaction: The updated transaction
    func updateTransaction(_ transaction: Transaction)

    /// Delete a transaction
    /// - Parameter transaction: The transaction to delete
    func deleteTransaction(_ transaction: Transaction)
}

/// Mode for adding transactions - affects how account names are handled
enum TransactionAddMode {
    case regular        // Normal transaction entry - derives account names from IDs
    case csvImport      // CSV import - preserves accountName and targetAccountName fields
}

/// Delegate protocol for TransactionCRUDService to communicate with ViewModel
@MainActor
protocol TransactionCRUDDelegate: AnyObject {
    // State access
    var allTransactions: [Transaction] { get set }
    var customCategories: [CustomCategory] { get set }
    var accounts: [Account] { get }
    var categoryRules: [CategoryRule] { get }
    var appSettings: AppSettings { get }

    // Dependencies
    var aggregateCache: CategoryAggregateCacheProtocol { get }
    var cacheManager: TransactionCacheManager { get }

    // Coordination methods
    func scheduleBalanceRecalculation()
    func scheduleSave()
    func rebuildIndexes()
    func invalidateCaches()
}
