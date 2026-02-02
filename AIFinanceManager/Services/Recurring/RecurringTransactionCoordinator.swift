//
//  RecurringTransactionCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//
//  Purpose: Single entry point for all recurring transaction operations
//  Architecture: Coordinates SubscriptionsViewModel, TransactionsViewModel, and RecurringTransactionGenerator
//

import Foundation

/// Coordinator for all recurring transaction operations
/// Provides single source of truth and eliminates duplication between ViewModels
@MainActor
class RecurringTransactionCoordinator: RecurringTransactionCoordinatorProtocol {

    // MARK: - Dependencies

    private weak var subscriptionsViewModel: SubscriptionsViewModel?
    private weak var transactionsViewModel: TransactionsViewModel?
    private let generator: RecurringTransactionGenerator
    private let validator: RecurringValidationService
    private let repository: DataRepositoryProtocol

    // MARK: - Initialization

    init(
        subscriptionsViewModel: SubscriptionsViewModel,
        transactionsViewModel: TransactionsViewModel,
        generator: RecurringTransactionGenerator,
        validator: RecurringValidationService,
        repository: DataRepositoryProtocol
    ) {
        self.subscriptionsViewModel = subscriptionsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.generator = generator
        self.validator = validator
        self.repository = repository
    }

    // MARK: - Series CRUD Operations

    func createSeries(_ series: RecurringSeries) async throws {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate series
        try validator.validate(series)

        // Create in SubscriptionsViewModel (single source of truth)
        subscriptionsVM.createSeriesInternal(series)

        // Generate transactions
        await generateAllTransactions(horizonMonths: 3)

        // If subscription, schedule notifications
        if series.isSubscription, series.subscriptionStatus == .active {
            if let nextChargeDate = nextChargeDate(for: series.id) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                    for: series,
                    nextChargeDate: nextChargeDate
                )
            }
        }
    }

    func updateSeries(_ series: RecurringSeries) async throws {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate series
        try validator.validate(series)

        // Find existing series
        let oldSeries = try validator.findSeries(id: series.id, in: subscriptionsVM.recurringSeries)

        // Update in SubscriptionsViewModel
        subscriptionsVM.updateSeriesInternal(series)

        // Check if regeneration needed
        if validator.needsRegeneration(oldSeries: oldSeries, newSeries: series) {
            // Delete future transactions for this series
            let today = Calendar.current.startOfDay(for: Date())
            let dateFormatter = DateFormatters.dateFormatter

            let futureOccurrences = transactionsVM.recurringOccurrences.filter { occurrence in
                guard occurrence.seriesId == series.id,
                      let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                    return false
                }
                return occurrenceDate > today
            }

            // Remove future transactions and occurrences
            for occurrence in futureOccurrences {
                transactionsVM.allTransactions.removeAll { $0.id == occurrence.transactionId }
                transactionsVM.recurringOccurrences.removeAll { $0.id == occurrence.id }
            }

            // Regenerate
            await generateAllTransactions(horizonMonths: 3)
        }

        // If subscription, update notifications
        if series.isSubscription {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
            if series.subscriptionStatus == .active {
                if let nextChargeDate = nextChargeDate(for: series.id) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                        for: series,
                        nextChargeDate: nextChargeDate
                    )
                }
            }
        }
    }

    func stopSeries(id seriesId: String, fromDate: String) async throws {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate series exists
        _ = try validator.findSeries(id: seriesId, in: subscriptionsVM.recurringSeries)

        // Stop in SubscriptionsViewModel
        subscriptionsVM.stopRecurringSeriesInternal(seriesId)

        // Delete future transactions
        let dateFormatter = DateFormatters.dateFormatter
        guard let txDate = dateFormatter.date(from: fromDate) else {
            throw RecurringTransactionError.invalidStartDate
        }
        let today = Calendar.current.startOfDay(for: Date())

        let futureOccurrences = transactionsVM.recurringOccurrences.filter { occurrence in
            guard occurrence.seriesId == seriesId,
                  let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                return false
            }
            return occurrenceDate > txDate && occurrenceDate > today
        }

        for occurrence in futureOccurrences {
            transactionsVM.allTransactions.removeAll { $0.id == occurrence.transactionId }
            transactionsVM.recurringOccurrences.removeAll { $0.id == occurrence.id }
        }

        // Recalculate balances
        transactionsVM.recalculateAccountBalances()
        transactionsVM.saveToStorage()

        // Cancel notifications if subscription
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
    }

    func deleteSeries(id seriesId: String, deleteTransactions: Bool) async throws {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate series exists
        _ = try validator.findSeries(id: seriesId, in: subscriptionsVM.recurringSeries)

        if deleteTransactions {
            // Remove all transactions
            transactionsVM.allTransactions.removeAll { $0.recurringSeriesId == seriesId }
        } else {
            // Convert to regular transactions (remove recurring IDs)
            var updatedTransactions: [Transaction] = []
            for transaction in transactionsVM.allTransactions {
                if transaction.recurringSeriesId == seriesId {
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
            transactionsVM.allTransactions = updatedTransactions
        }

        // Remove occurrences
        transactionsVM.recurringOccurrences.removeAll { $0.seriesId == seriesId }

        // Delete from SubscriptionsViewModel
        subscriptionsVM.deleteRecurringSeriesInternal(seriesId, deleteTransactions: deleteTransactions)

        // Recalculate balances and rebuild indexes
        transactionsVM.invalidateCaches()
        transactionsVM.rebuildIndexes()
        transactionsVM.scheduleBalanceRecalculation()
        transactionsVM.scheduleSave()

        // Cancel notifications
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
    }

    // MARK: - Transaction Generation

    func generateAllTransactions(horizonMonths: Int = 3) async {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel else {
            return
        }

        PerformanceProfiler.start("RecurringCoordinator.generateAllTransactions")
        defer { PerformanceProfiler.end("RecurringCoordinator.generateAllTransactions") }

        // Reload latest data from repository to ensure consistency
        let latestSeries = repository.loadRecurringSeries()
        let latestOccurrences = repository.loadRecurringOccurrences()

        // Skip if no active series
        guard !latestSeries.filter({ $0.isActive }).isEmpty else {
            return
        }

        // Generate new transactions
        let existingTransactionIds = Set(transactionsVM.allTransactions.map { $0.id })
        let (newTransactions, newOccurrences) = generator.generateTransactions(
            series: latestSeries,
            existingOccurrences: latestOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: transactionsVM.accounts,
            horizonMonths: horizonMonths
        )

        // Insert new transactions
        if !newTransactions.isEmpty {
            transactionsVM.insertTransactionsSorted(newTransactions)
            transactionsVM.recurringOccurrences.append(contentsOf: newOccurrences)
        }

        // Convert past recurring to regular
        let updatedAllTransactions = generator.convertPastRecurringToRegular(transactionsVM.allTransactions)
        let convertedCount = zip(transactionsVM.allTransactions, updatedAllTransactions)
            .filter { $0.0.recurringSeriesId != $0.1.recurringSeriesId }
            .count

        if convertedCount > 0 {
            transactionsVM.allTransactions = updatedAllTransactions
        }

        // Save if there were changes
        let needsSave = !newTransactions.isEmpty || convertedCount > 0
        if needsSave {
            transactionsVM.scheduleBalanceRecalculation()
            transactionsVM.scheduleSave()

            // Schedule notifications for active subscriptions
            for series in latestSeries where series.isSubscription && series.subscriptionStatus == .active {
                if let nextCharge = nextChargeDate(for: series.id) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                        for: series,
                        nextChargeDate: nextCharge
                    )
                }
            }
        }
    }

    func getPlannedTransactions(for seriesId: String, horizonMonths: Int = 3) -> [Transaction] {
        guard let subscriptionsVM = subscriptionsViewModel,
              let transactionsVM = transactionsViewModel,
              let series = subscriptionsVM.recurringSeries.first(where: { $0.id == seriesId }) else {
            return []
        }

        // Get existing transactions for this series
        let existingTransactions = transactionsVM.allTransactions.filter { $0.recurringSeriesId == seriesId }

        // Generate planned future transactions for display
        let existingIds = Set(existingTransactions.map { $0.id })
        let existingOccurrences = transactionsVM.recurringOccurrences.filter { $0.seriesId == seriesId }

        let (plannedTransactions, _) = generator.generateTransactions(
            series: [series],
            existingOccurrences: existingOccurrences,
            existingTransactionIds: existingIds,
            accounts: transactionsVM.accounts,
            horizonMonths: horizonMonths
        )

        // Combine existing + planned, sorted by date descending
        return (existingTransactions + plannedTransactions).sorted { $0.date > $1.date }
    }

    // MARK: - Subscription-Specific Operations

    func pauseSubscription(id subscriptionId: String) async throws {
        guard let subscriptionsVM = subscriptionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate is subscription
        _ = try validator.findSubscription(id: subscriptionId, in: subscriptionsVM.recurringSeries)

        // Pause in SubscriptionsViewModel
        subscriptionsVM.pauseSubscriptionInternal(subscriptionId)

        // Cancel notifications
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: subscriptionId)
    }

    func resumeSubscription(id subscriptionId: String) async throws {
        guard let subscriptionsVM = subscriptionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate is subscription
        let subscription = try validator.findSubscription(id: subscriptionId, in: subscriptionsVM.recurringSeries)

        // Resume in SubscriptionsViewModel
        subscriptionsVM.resumeSubscriptionInternal(subscriptionId)

        // Schedule notifications
        if let nextCharge = nextChargeDate(for: subscriptionId) {
            await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                for: subscription,
                nextChargeDate: nextCharge
            )
        }
    }

    func archiveSubscription(id subscriptionId: String) async throws {
        guard let subscriptionsVM = subscriptionsViewModel else {
            throw RecurringTransactionError.coordinatorNotInitialized
        }

        // Validate is subscription
        _ = try validator.findSubscription(id: subscriptionId, in: subscriptionsVM.recurringSeries)

        // Archive in SubscriptionsViewModel
        subscriptionsVM.archiveSubscriptionInternal(subscriptionId)

        // Cancel notifications
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: subscriptionId)
    }

    func nextChargeDate(for subscriptionId: String) -> Date? {
        guard let subscriptionsVM = subscriptionsViewModel,
              let series = subscriptionsVM.recurringSeries.first(where: { $0.id == subscriptionId && $0.isSubscription }) else {
            return nil
        }
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }
}
