//
//  RecurringTransactionService.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Service responsible for recurring transaction operations
/// Extracted from TransactionsViewModel to follow Single Responsibility Principle
@MainActor
class RecurringTransactionService: RecurringTransactionServiceProtocol {

    // MARK: - Dependencies

    private weak var delegate: RecurringTransactionServiceDelegate?

    // MARK: - Initialization

    init(delegate: RecurringTransactionServiceDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Public API

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
    ) -> RecurringSeries {
        guard let delegate = delegate else {
            fatalError("Delegate is nil")
        }

        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category,
            subcategory: subcategory,
            description: description,
            accountId: accountId,
            targetAccountId: targetAccountId,
            frequency: frequency,
            startDate: startDate
        )
        delegate.recurringSeries.append(series)
        delegate.saveToStorageDebounced()
        generateRecurringTransactions()
        return series
    }

    func updateRecurringSeries(_ series: RecurringSeries) {
        guard let delegate = delegate else { return }

        if let index = delegate.recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = delegate.recurringSeries[index]
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate

            delegate.recurringSeries[index] = series

            if frequencyChanged || startDateChanged {
                let today = Calendar.current.startOfDay(for: Date())
                let dateFormatter = DateFormatters.dateFormatter

                let futureOccurrences = delegate.recurringOccurrences.filter { occurrence in
                    guard occurrence.seriesId == series.id,
                          let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                        return false
                    }
                    return occurrenceDate > today
                }

                for occurrence in futureOccurrences {
                    delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
                    delegate.recurringOccurrences.removeAll { $0.id == occurrence.id }
                }
            }

            delegate.saveToStorageDebounced()
            generateRecurringTransactions()
        }
    }

    func stopRecurringSeries(_ seriesId: String) {
        guard let delegate = delegate else { return }

        if let index = delegate.recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            delegate.recurringSeries[index].isActive = false
            delegate.saveToStorageDebounced()
        }
    }

    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String) {
        guard let delegate = delegate else { return }

        stopRecurringSeries(seriesId)

        let dateFormatter = DateFormatters.dateFormatter
        guard let txDate = dateFormatter.date(from: transactionDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Удаляем все будущие транзакции этой серии
        let futureOccurrences = delegate.recurringOccurrences.filter { occurrence in
            guard occurrence.seriesId == seriesId,
                  let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                return false
            }
            return occurrenceDate > txDate && occurrenceDate > today
        }

        for occurrence in futureOccurrences {
            delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
            delegate.recurringOccurrences.removeAll { $0.id == occurrence.id }
        }

        delegate.recalculateAccountBalances()
        delegate.saveToStorage()
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        guard let delegate = delegate else { return }

        if deleteTransactions {
            // Remove transactions
            delegate.allTransactions.removeAll { $0.recurringSeriesId == seriesId }
        } else {
            // Clear the recurring series link, transactions become regular
            var updatedTransactions: [Transaction] = []
            for transaction in delegate.allTransactions {
                if transaction.recurringSeriesId == seriesId {
                    // Create new transaction without recurring IDs
                    let updatedTransaction = Transaction(
                        id: transaction.id,
                        date: transaction.date,
                        description: transaction.description,
                        amount: transaction.amount,
                        currency: transaction.currency,
                        convertedAmount: transaction.convertedAmount,
                        type: transaction.type,
                        category: transaction.category,
                        subcategory: transaction.subcategory,
                        accountId: transaction.accountId,
                        targetAccountId: transaction.targetAccountId,
                        accountName: transaction.accountName,
                        targetAccountName: transaction.targetAccountName,
                        targetCurrency: transaction.targetCurrency,
                        targetAmount: transaction.targetAmount,
                        recurringSeriesId: nil,
                        recurringOccurrenceId: nil,
                        createdAt: transaction.createdAt
                    )
                    updatedTransactions.append(updatedTransaction)
                } else {
                    updatedTransactions.append(transaction)
                }
            }
            delegate.allTransactions = updatedTransactions
        }

        // Remove occurrences
        delegate.recurringOccurrences.removeAll { $0.seriesId == seriesId }

        // Remove series
        delegate.recurringSeries.removeAll { $0.id == seriesId }

        // CRITICAL: Recalculate balances after deleting transactions
        delegate.invalidateCaches()
        delegate.rebuildIndexes()
        delegate.scheduleBalanceRecalculation()
        delegate.scheduleSave()

        // Cancel notifications
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }
    }

    func archiveSubscription(_ seriesId: String) {
        guard let delegate = delegate else { return }

        if let index = delegate.recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            delegate.recurringSeries[index].status = .archived
            delegate.recurringSeries[index].isActive = false
            delegate.saveToStorageDebounced()

            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }

    func generateRecurringTransactions() {
        guard let delegate = delegate else { return }

        PerformanceProfiler.start("generateRecurringTransactions")

        defer {
            PerformanceProfiler.end("generateRecurringTransactions")
        }

        // REFACTORED 2026-02-02: recurringSeries is now computed from SubscriptionsViewModel (Single Source of Truth)
        // No need to reload - it's always up to date from SubscriptionsViewModel
        // Still reload recurringOccurrences to prevent deleted ones from being restored
        delegate.recurringOccurrences = delegate.repository.loadRecurringOccurrences()

        // Skip if no active recurring series
        if delegate.recurringSeries.filter({ $0.isActive }).isEmpty {
            return
        }

        // Delegate generation to recurringGenerator service
        let existingTransactionIds = Set(delegate.allTransactions.map { $0.id })
        let (newTransactions, newOccurrences) = delegate.recurringGenerator.generateTransactions(
            series: delegate.recurringSeries,
            existingOccurrences: delegate.recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: delegate.accounts,
            horizonMonths: 3
        )

        // First, insert new transactions if any
        if !newTransactions.isEmpty {
            delegate.insertTransactionsSorted(newTransactions)
            delegate.recurringOccurrences.append(contentsOf: newOccurrences)
        }

        // Now convert past recurring transactions to regular transactions
        // This must happen AFTER insertion to catch newly created transactions with past dates
        let updatedAllTransactions = delegate.recurringGenerator.convertPastRecurringToRegular(delegate.allTransactions)
        let convertedCount = zip(delegate.allTransactions, updatedAllTransactions).filter { $0.0.recurringSeriesId != $0.1.recurringSeriesId }.count

        // Reassign to trigger @Published if conversions happened
        let needsSave = !newTransactions.isEmpty || convertedCount > 0
        if convertedCount > 0 {
            delegate.allTransactions = updatedAllTransactions
        }

        // Recalculate and save if there were any changes
        if needsSave {
            delegate.scheduleBalanceRecalculation()
            delegate.scheduleSave()

            Task {
                for series in delegate.recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        }
    }

    /// DEPRECATED 2026-02-02: This method is not used anywhere (73 LOC of dead code)
    /// Use RecurringTransactionCoordinator.updateSeries() instead
    /// NOTE: This method tries to modify delegate.recurringSeries which is now read-only (computed property)
    @available(*, deprecated, message: "Use RecurringTransactionCoordinator.updateSeries() instead. Will be removed in future version.")
    func updateRecurringTransaction(
        _ transactionId: String,
        updateAllFuture: Bool,
        newAmount: Decimal? = nil,
        newCategory: String? = nil,
        newSubcategory: String? = nil
    ) {
        guard let delegate = delegate else { return }

        guard let transaction = delegate.allTransactions.first(where: { $0.id == transactionId }),
              let seriesId = transaction.recurringSeriesId,
              let seriesIndex = delegate.recurringSeries.firstIndex(where: { $0.id == seriesId }) else {
            return
        }

        if updateAllFuture {
            if let newAmount = newAmount {
                delegate.recurringSeries[seriesIndex].amount = newAmount
            }
            if let newCategory = newCategory {
                delegate.recurringSeries[seriesIndex].category = newCategory
            }
            if let newSubcategory = newSubcategory {
                delegate.recurringSeries[seriesIndex].subcategory = newSubcategory
            }

            let dateFormatter = DateFormatters.dateFormatter
            guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }

            let futureOccurrences = delegate.recurringOccurrences.filter { occurrence in
                guard occurrence.seriesId == seriesId,
                      let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                    return false
                }
                return occurrenceDate >= transactionDate
            }

            for occurrence in futureOccurrences {
                delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
                delegate.recurringOccurrences.removeAll { $0.id == occurrence.id }
            }

            generateRecurringTransactions()
        } else {
            if let index = delegate.allTransactions.firstIndex(where: { $0.id == transactionId }) {
                var updatedTransaction = delegate.allTransactions[index]
                if let newAmount = newAmount {
                    let amountDouble = NSDecimalNumber(decimal: newAmount).doubleValue
                    updatedTransaction = Transaction(
                        id: updatedTransaction.id,
                        date: updatedTransaction.date,
                        description: updatedTransaction.description,
                        amount: amountDouble,
                        currency: updatedTransaction.currency,
                        convertedAmount: updatedTransaction.convertedAmount,
                        type: updatedTransaction.type,
                        category: newCategory ?? updatedTransaction.category,
                        subcategory: newSubcategory ?? updatedTransaction.subcategory,
                        accountId: updatedTransaction.accountId,
                        targetAccountId: updatedTransaction.targetAccountId,
                        targetCurrency: updatedTransaction.targetCurrency,
                        targetAmount: updatedTransaction.targetAmount,
                        recurringSeriesId: updatedTransaction.recurringSeriesId,
                        recurringOccurrenceId: updatedTransaction.recurringOccurrenceId,
                        createdAt: updatedTransaction.createdAt
                    )
                    delegate.allTransactions[index] = updatedTransaction
                }
            }
        }

        delegate.saveToStorageDebounced()
    }

    func nextChargeDate(for subscriptionId: String) -> Date? {
        guard let delegate = delegate else { return nil }

        guard let series = delegate.recurringSeries.first(where: { $0.id == subscriptionId && $0.isSubscription }) else {
            return nil
        }
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }
}
