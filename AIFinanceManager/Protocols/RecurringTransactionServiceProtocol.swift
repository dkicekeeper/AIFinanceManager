//
//  RecurringTransactionServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Protocol defining recurring transaction operations
/// Follows Single Responsibility Principle - handles only recurring logic
@MainActor
protocol RecurringTransactionServiceProtocol {
    /// Create a new recurring series
    func createRecurringSeries(
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String?,
        description: String,
        accountId: String?,
        targetAccountId: String?,
        frequency: RecurringFrequency,
        startDate: String
    ) -> RecurringSeries

    /// Update an existing recurring series
    func updateRecurringSeries(_ series: RecurringSeries)

    /// Stop a recurring series (set isActive = false)
    func stopRecurringSeries(_ seriesId: String)

    /// Stop recurring series and cleanup all future transactions
    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String)

    /// Delete recurring series and optionally its transactions
    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool)

    /// Archive a subscription
    func archiveSubscription(_ seriesId: String)

    /// Generate recurring transactions for all active series
    func generateRecurringTransactions()

    /// Update a single recurring transaction (this occurrence or all future)
    func updateRecurringTransaction(
        _ transactionId: String,
        updateAllFuture: Bool,
        newAmount: Decimal?,
        newCategory: String?,
        newSubcategory: String?
    )

    /// Calculate next charge date for subscription
    func nextChargeDate(for subscriptionId: String) -> Date?
}

/// Delegate protocol for RecurringTransactionService to access ViewModel state
@MainActor
protocol RecurringTransactionServiceDelegate: AnyObject {
    // State access
    var allTransactions: [Transaction] { get set }
    var recurringSeries: [RecurringSeries] { get set }
    var recurringOccurrences: [RecurringOccurrence] { get set }
    var accounts: [Account] { get }

    // Dependencies
    var repository: DataRepositoryProtocol { get }
    var recurringGenerator: RecurringTransactionGenerator { get }

    // Coordination methods
    func insertTransactionsSorted(_ newTransactions: [Transaction])
    func invalidateCaches()
    func rebuildIndexes()
    func scheduleBalanceRecalculation()
    func scheduleSave()
    func saveToStorageDebounced()
    func recalculateAccountBalances()
    func saveToStorage()
}
