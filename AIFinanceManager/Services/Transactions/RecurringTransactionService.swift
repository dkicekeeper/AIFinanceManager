//
//  RecurringTransactionService.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Service responsible for recurring transaction operations
/// Extracted from TransactionsViewModel to follow Single Responsibility Principle
///
/// ⚠️ DEPRECATED 2026-02-02: This service is deprecated in favor of RecurringTransactionCoordinator
/// Most methods cannot work anymore because recurringSeries is now a read-only computed property
/// Use RecurringTransactionCoordinator for all recurring operations
@MainActor
class RecurringTransactionService: RecurringTransactionServiceProtocol {

    // MARK: - Dependencies

    private weak var delegate: RecurringTransactionServiceDelegate?

    // MARK: - Initialization

    init(delegate: RecurringTransactionServiceDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Public API

    /// ⚠️ DEPRECATED: Cannot mutate read-only recurringSeries. Use RecurringTransactionCoordinator.createSeries()
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
        // NOTE: Cannot append to read-only recurringSeries
        // Use RecurringTransactionCoordinator.createSeries() instead
        // delegate.recurringSeries.append(series)
        delegate.saveToStorageDebounced()
        generateRecurringTransactions()
        return series
    }

    /// ⚠️ DEPRECATED: Cannot mutate read-only recurringSeries. Use RecurringTransactionCoordinator.updateSeries()
    func updateRecurringSeries(_ series: RecurringSeries) {
        guard let delegate = delegate else { return }

        if let index = delegate.recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = delegate.recurringSeries[index]
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate

            // NOTE: Cannot assign to read-only recurringSeries
            // Use RecurringTransactionCoordinator.updateSeries() instead
            // delegate.recurringSeries[index] = series

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

                // 🔧 FIX 2026-02-08: Delete future transactions from TransactionStore (database)
                // ⚠️ CRITICAL FIX: Must wait for deletion to complete using semaphore
                if let transactionStore = delegate.transactionStore {
                    let transactionsToDelete = delegate.allTransactions.filter { tx in
                        futureOccurrences.contains { $0.transactionId == tx.id }
                    }

                    #if DEBUG
                    print("🗑️ [RecurringTransactionService] Updating series \(series.id): deleting \(transactionsToDelete.count) future transactions (BLOCKING)")
                    #endif

                    let semaphore = DispatchSemaphore(value: 0)

                    Task { @MainActor in
                        for transaction in transactionsToDelete {
                            do {
                                try await transactionStore.delete(transaction)
                            } catch {
                                print("   ⚠️ Failed to delete transaction: \(error)")
                            }
                        }
                        semaphore.signal()
                    }

                    semaphore.wait()

                    #if DEBUG
                    print("✅ [RecurringTransactionService] Update deletion completed")
                    #endif
                } else {
                    // Fallback: legacy path
                    for occurrence in futureOccurrences {
                        delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
                    }
                }

                // Remove occurrences (now safe - deletions completed)
                for occurrence in futureOccurrences {
                    delegate.recurringOccurrences.removeAll { $0.id == occurrence.id }
                }
            }

            delegate.saveToStorageDebounced()
            generateRecurringTransactions()
        }
    }

    /// ⚠️ DEPRECATED: Cannot mutate read-only recurringSeries. Use RecurringTransactionCoordinator.stopSeries()
    func stopRecurringSeries(_ seriesId: String) {
        guard let delegate = delegate else { return }

        if let _ = delegate.recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            // NOTE: Cannot modify read-only recurringSeries
            // Use RecurringTransactionCoordinator.stopSeries() instead
            // delegate.recurringSeries[index].isActive = false
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

        // 🔧 FIX 2026-02-08: Delete future transactions from TransactionStore (database)
        // ⚠️ CRITICAL FIX: Deletions were async and didn't complete before method returned!
        // Solution: Use DispatchSemaphore to wait for async deletion to complete
        if let transactionStore = delegate.transactionStore {
            // Find transactions to delete
            let transactionsToDelete = delegate.allTransactions.filter { tx in
                futureOccurrences.contains { $0.transactionId == tx.id }
            }

            #if DEBUG
            print("🗑️ [RecurringTransactionService] Stopping series \(seriesId): deleting \(transactionsToDelete.count) future transactions (BLOCKING)")
            #endif

            // Use semaphore to block until deletion completes
            let semaphore = DispatchSemaphore(value: 0)

            Task { @MainActor in
                for transaction in transactionsToDelete {
                    do {
                        try await transactionStore.delete(transaction)
                        #if DEBUG
                        print("   ✅ Deleted future: \(transaction.description) - \(transaction.date)")
                        #endif
                    } catch {
                        print("   ⚠️ Failed to delete transaction: \(error)")
                    }
                }
                semaphore.signal() // Signal completion
            }

            // ⚠️ BLOCK until deletion completes
            semaphore.wait()

            #if DEBUG
            print("✅ [RecurringTransactionService] Deletion completed, continuing...")
            #endif
        } else {
            // Fallback: remove from memory only (legacy path)
            #if DEBUG
            print("⚠️ [RecurringTransactionService] TransactionStore NOT available, using legacy path for stopping series")
            #endif
            for occurrence in futureOccurrences {
                delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
            }
        }

        // Remove occurrences (now safe - deletions completed)
        for occurrence in futureOccurrences {
            delegate.recurringOccurrences.removeAll { $0.id == occurrence.id }
        }

        delegate.recalculateAccountBalances()
        delegate.saveToStorage()
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        guard let delegate = delegate else { return }

        if deleteTransactions {
            // 🔧 FIX 2026-02-08: Delete transactions from TransactionStore (database)
            // ⚠️ CRITICAL FIX: Must wait for deletion to complete using semaphore
            if let transactionStore = delegate.transactionStore {
                // Find all transactions for this series
                let transactionsToDelete = delegate.allTransactions.filter { $0.recurringSeriesId == seriesId }

                #if DEBUG
                print("🗑️ [RecurringTransactionService] Deleting \(transactionsToDelete.count) transactions for series \(seriesId) (BLOCKING)")
                #endif

                // Use semaphore to block until deletion completes
                let semaphore = DispatchSemaphore(value: 0)

                Task { @MainActor in
                    for transaction in transactionsToDelete {
                        do {
                            try await transactionStore.delete(transaction)
                            #if DEBUG
                            print("   ✅ Deleted: \(transaction.description) - \(transaction.amount) \(transaction.currency)")
                            #endif
                        } catch {
                            print("   ⚠️ Failed to delete transaction: \(error)")
                        }
                    }
                    semaphore.signal()
                }

                // ⚠️ BLOCK until deletion completes
                semaphore.wait()

                #if DEBUG
                print("✅ [RecurringTransactionService] Deletion completed")
                #endif
            } else {
                // Fallback: remove from memory only (legacy path)
                #if DEBUG
                print("⚠️ [RecurringTransactionService] TransactionStore NOT available, using legacy deletion path")
                #endif
                delegate.allTransactions.removeAll { $0.recurringSeriesId == seriesId }
            }
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

        // NOTE: Cannot remove from read-only recurringSeries
        // Use RecurringTransactionCoordinator.deleteSeries() instead
        // delegate.recurringSeries.removeAll { $0.id == seriesId }

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

    /// ⚠️ DEPRECATED: Cannot mutate read-only recurringSeries. Use RecurringTransactionCoordinator.archiveSubscription()
    func archiveSubscription(_ seriesId: String) {
        guard let delegate = delegate else { return }

        if let _ = delegate.recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            // NOTE: Cannot modify read-only recurringSeries
            // Use RecurringTransactionCoordinator.archiveSubscription() instead
            // delegate.recurringSeries[index].status = .archived
            // delegate.recurringSeries[index].isActive = false
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
            baseCurrency: delegate.appSettings.baseCurrency,
            horizonMonths: 3
        )

        // First, insert new transactions if any
        if !newTransactions.isEmpty {
            #if DEBUG
            print("🔄 [RecurringTransactionService] Generated \(newTransactions.count) new transactions")
            for tx in newTransactions.prefix(3) {
                print("   📝 \(tx.description) - \(tx.amount) \(tx.currency) - category: \(tx.category) - account: \(tx.accountId ?? "nil")")
            }
            #endif

            // 🔧 CRITICAL FIX: Add transactions to TransactionStore ONLY
            // TransactionStore will propagate changes back to TransactionsViewModel via observer
            // This ensures Single Source of Truth and avoids duplicate transactions
            if let transactionStore = delegate.transactionStore {
                #if DEBUG
                print("✅ [RecurringTransactionService] TransactionStore available, adding transactions...")
                print("   📊 TransactionStore has \(transactionStore.accounts.count) accounts, \(transactionStore.categories.count) categories")
                #endif

                // Add to TransactionStore (will sync back to allTransactions via observer)
                // IMPORTANT: Use Task and await to ensure transactions are added before balance recalculation
                Task { @MainActor in
                    var successCount = 0
                    var failCount = 0

                    for transaction in newTransactions {
                        do {
                            _ = try await transactionStore.add(transaction)
                            successCount += 1
                        } catch {
                            failCount += 1
                            print("⚠️ [RecurringTransactionService] Failed to add transaction to store: \(error)")
                            print("   📝 Transaction: \(transaction.description) - category: \(transaction.category) - account: \(transaction.accountId ?? "nil")")
                        }
                    }

                    #if DEBUG
                    print("✅ [RecurringTransactionService] Added \(successCount)/\(newTransactions.count) transactions to TransactionStore")
                    if failCount > 0 {
                        print("⚠️ [RecurringTransactionService] Failed to add \(failCount) transactions")
                    }
                    print("🔄 [RecurringTransactionService] About to recalculate balances...")
                    print("   📊 Current state:")
                    print("      - TransactionStore.transactions: \(transactionStore.transactions.count)")
                    print("      - TransactionStore.accounts: \(transactionStore.accounts.count)")
                    print("      - delegate.allTransactions: \(delegate.allTransactions.count)")
                    print("      - delegate.accounts: \(delegate.accounts.count)")
                    #endif

                    // ✅ CRITICAL: Only recalculate balances AFTER transactions are added to store
                    // This ensures TransactionStore has the latest data
                    delegate.scheduleBalanceRecalculation()
                    delegate.scheduleSave()

                    #if DEBUG
                    print("✅ [RecurringTransactionService] Balance recalculation scheduled")
                    #endif

                    // Schedule notifications for subscriptions
                    for series in delegate.recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                        if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                            await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                        }
                    }
                }
            } else {
                // Fallback: add directly if TransactionStore not available (legacy path)
                #if DEBUG
                print("⚠️ [RecurringTransactionService] TransactionStore NOT available, using legacy path")
                #endif

                delegate.insertTransactionsSorted(newTransactions)

                // For legacy path, recalculate immediately
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

            delegate.recurringOccurrences.append(contentsOf: newOccurrences)
        }

        // Now convert past recurring transactions to regular transactions
        // This must happen AFTER insertion to catch newly created transactions with past dates
        let updatedAllTransactions = delegate.recurringGenerator.convertPastRecurringToRegular(delegate.allTransactions)
        let convertedCount = zip(delegate.allTransactions, updatedAllTransactions).filter { $0.0.recurringSeriesId != $0.1.recurringSeriesId }.count

        // Reassign to trigger @Published if conversions happened
        if convertedCount > 0 {
            delegate.allTransactions = updatedAllTransactions
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
              delegate.recurringSeries.firstIndex(where: { $0.id == seriesId }) != nil else {
            return
        }

        if updateAllFuture {
            // NOTE: Cannot modify read-only recurringSeries
            // Use RecurringTransactionCoordinator.updateSeries() instead
            // if let newAmount = newAmount {
            //     delegate.recurringSeries[seriesIndex].amount = newAmount
            // }
            // if let newCategory = newCategory {
            //     delegate.recurringSeries[seriesIndex].category = newCategory
            // }
            // if let newSubcategory = newSubcategory {
            //     delegate.recurringSeries[seriesIndex].subcategory = newSubcategory
            // }

            let dateFormatter = DateFormatters.dateFormatter
            guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }

            let futureOccurrences = delegate.recurringOccurrences.filter { occurrence in
                guard occurrence.seriesId == seriesId,
                      let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                    return false
                }
                return occurrenceDate >= transactionDate
            }

            // 🔧 FIX 2026-02-08: Delete future transactions from TransactionStore (database)
            // ⚠️ CRITICAL FIX: Must wait for deletion to complete using semaphore
            if let transactionStore = delegate.transactionStore {
                let transactionsToDelete = delegate.allTransactions.filter { tx in
                    futureOccurrences.contains { $0.transactionId == tx.id }
                }

                #if DEBUG
                print("🗑️ [RecurringTransactionService] Updating transaction \(transactionId): deleting \(transactionsToDelete.count) future transactions (BLOCKING)")
                #endif

                let semaphore = DispatchSemaphore(value: 0)

                Task { @MainActor in
                    for transaction in transactionsToDelete {
                        do {
                            try await transactionStore.delete(transaction)
                        } catch {
                            print("   ⚠️ Failed to delete transaction: \(error)")
                        }
                    }
                    semaphore.signal()
                }

                semaphore.wait()

                #if DEBUG
                print("✅ [RecurringTransactionService] Update transaction deletion completed")
                #endif
            } else {
                // Fallback: legacy path
                for occurrence in futureOccurrences {
                    delegate.allTransactions.removeAll { $0.id == occurrence.transactionId }
                }
            }

            // Remove occurrences (now safe - deletions completed)
            for occurrence in futureOccurrences {
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
