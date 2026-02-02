//
//  SubscriptionsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing subscriptions and recurring transactions

import Foundation
import SwiftUI
import Combine

@MainActor
class SubscriptionsViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var recurringSeries: [RecurringSeries] = []
    @Published var recurringOccurrences: [RecurringOccurrence] = []
    
    // MARK: - Private Properties
    
    private let repository: DataRepositoryProtocol
    
    // MARK: - Computed Properties
    
    /// Get all subscriptions
    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }
    
    /// Get active subscriptions
    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        self.recurringSeries = repository.loadRecurringSeries()
        self.recurringOccurrences = repository.loadRecurringOccurrences()
    }
    
    // MARK: - Recurring Series CRUD Operations

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

        // ✅ CRITICAL: Reassign array to trigger @Published
        // Using append() doesn't always trigger SwiftUI updates
        recurringSeries = recurringSeries + [series]

        saveRecurringSeries()  // ✅ Sync save

        // Notify TransactionsViewModel to generate transactions for new series
        NotificationCenter.default.post(
            name: .recurringSeriesCreated,
            object: nil,
            userInfo: ["seriesId": series.id]
        )

        return series
    }

    func updateRecurringSeries(_ series: RecurringSeries) {
        updateSeriesInternal(series, scheduleNotifications: false)
    }
    
    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            // Создаем новый массив и модифицируем элемент
            var newSeries = recurringSeries
            newSeries[index].isActive = false

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            // NOTE: @Published automatically sends objectWillChange notification

            saveRecurringSeries()  // ✅ Sync save
        }
    }
    
    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {

        // ✅ CRITICAL: Use filter to create new array for @Published trigger
        recurringOccurrences = recurringOccurrences.filter { $0.seriesId != seriesId }
        recurringSeries = recurringSeries.filter { $0.id != seriesId }


        saveRecurringSeries()  // ✅ Sync save
        repository.saveRecurringOccurrences(recurringOccurrences)

        // Cancel notifications for subscriptions
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }

        // Note: Transaction deletion is handled by TransactionsViewModel
    }
    
    // MARK: - Subscription Operations
    
    /// Create a new subscription
    func createSubscription(
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String?,
        description: String,
        accountId: String?,
        frequency: RecurringFrequency,
        startDate: String,
        brandLogo: BankLogo?,
        brandId: String?,
        reminderOffsets: [Int]?
    ) -> RecurringSeries {
        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category,
            subcategory: subcategory,
            description: description,
            accountId: accountId,
            targetAccountId: nil,
            frequency: frequency,
            startDate: startDate,
            kind: .subscription,
            brandLogo: brandLogo,
            brandId: brandId,
            reminderOffsets: reminderOffsets,
            status: .active
        )
        
        // ✅ CRITICAL: Reassign array to trigger @Published
        // Using append() doesn't always trigger SwiftUI updates
        recurringSeries = recurringSeries + [series]
        
        saveRecurringSeries()  // ✅ Sync save
        
        // Notify TransactionsViewModel to generate transactions for new subscription
        NotificationCenter.default.post(
            name: .recurringSeriesCreated,
            object: nil,
            userInfo: ["seriesId": series.id]
        )
        
        // Schedule notifications
        scheduleNotificationsForSubscription(series)

        return series
    }
    
    /// Update a subscription
    func updateSubscription(_ series: RecurringSeries) {
        updateSeriesInternal(series, scheduleNotifications: true)
    }
    
    /// Pause a subscription
    func pauseSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            // Создаем новый массив и модифицируем элемент
            var newSeries = recurringSeries
            newSeries[index].status = .paused
            newSeries[index].isActive = false

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            // NOTE: @Published automatically sends objectWillChange notification

            saveRecurringSeries()  // ✅ Sync save

            // Cancel notifications
            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }
    
    /// Resume a subscription
    func resumeSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            // Создаем новый массив и модифицируем элемент
            var newSeries = recurringSeries
            newSeries[index].status = .active
            newSeries[index].isActive = true

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries

            saveRecurringSeries()

            // Schedule notifications
            scheduleNotificationsForSubscription(recurringSeries[index])
        }
    }
    
    /// Archive a subscription
    func archiveSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            // Создаем новый массив и модифицируем элемент
            var newSeries = recurringSeries
            newSeries[index].status = .archived
            newSeries[index].isActive = false

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            // NOTE: @Published automatically sends objectWillChange notification

            saveRecurringSeries()  // ✅ Sync save

            // Cancel notifications
            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get next charge date for a subscription
    func nextChargeDate(for subscriptionId: String) -> Date? {
        guard let series = recurringSeries.first(where: { $0.id == subscriptionId && $0.isSubscription }) else {
            return nil
        }
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }
    
    /// Get recurring series by ID
    func getRecurringSeries(by id: String) -> RecurringSeries? {
        return recurringSeries.first { $0.id == id }
    }
    
    // MARK: - Private Helpers

    /// Unified update method for both recurring series and subscriptions
    /// - Parameters:
    ///   - series: The series to update
    ///   - scheduleNotifications: Whether to schedule/update notifications (subscriptions only)
    private func updateSeriesInternal(_ series: RecurringSeries, scheduleNotifications: Bool) {
        guard let index = recurringSeries.firstIndex(where: { $0.id == series.id }) else { return }

        let oldSeries = recurringSeries[index]

        // Check if need to regenerate future transactions
        let frequencyChanged = oldSeries.frequency != series.frequency
        let startDateChanged = oldSeries.startDate != series.startDate
        let amountChanged = oldSeries.amount != series.amount
        let needsRegeneration = frequencyChanged || startDateChanged || amountChanged

        // Создаем новый массив вместо модификации элемента на месте
        var newSeries = recurringSeries
        newSeries[index] = series

        // Переприсваиваем весь массив для триггера @Published
        recurringSeries = newSeries

        // Notify TransactionsViewModel to regenerate if needed
        if needsRegeneration {
            NotificationCenter.default.post(
                name: .recurringSeriesChanged,
                object: nil,
                userInfo: ["seriesId": series.id, "oldSeries": oldSeries]
            )
        }

        saveRecurringSeries()

        // Schedule notifications for subscriptions if requested
        if scheduleNotifications {
            scheduleNotificationsForSubscription(series)
        }
    }

    /// Schedule or cancel notifications for a subscription based on its status
    /// - Parameter series: The subscription series to schedule notifications for
    private func scheduleNotificationsForSubscription(_ series: RecurringSeries) {
        Task {
            if series.subscriptionStatus == .active {
                if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                        for: series,
                        nextChargeDate: nextChargeDate
                    )
                }
            } else {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
            }
        }
    }

    /// Save recurring series
    /// Note: Uses async save through SaveCoordinator for proper Core Data handling
    /// Recurring series have complex relationships that require background context
    private func saveRecurringSeries() {
        repository.saveRecurringSeries(recurringSeries)
    }

    // MARK: - Internal Methods (for RecurringTransactionCoordinator)

    /// Internal method to create a series without notifications
    /// Used by RecurringTransactionCoordinator to avoid duplication
    func createSeriesInternal(_ series: RecurringSeries) {
        // ✅ CRITICAL: Reassign array to trigger @Published
        recurringSeries = recurringSeries + [series]
        saveRecurringSeries()
    }

    /// Internal method to update a series without notifications
    /// Used by RecurringTransactionCoordinator
    func updateSeriesInternal(_ series: RecurringSeries) {
        guard let index = recurringSeries.firstIndex(where: { $0.id == series.id }) else { return }

        var newSeries = recurringSeries
        newSeries[index] = series
        recurringSeries = newSeries

        saveRecurringSeries()
    }

    /// Internal method to stop a series
    /// Used by RecurringTransactionCoordinator
    func stopRecurringSeriesInternal(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            var newSeries = recurringSeries
            newSeries[index].isActive = false
            recurringSeries = newSeries
            saveRecurringSeries()
        }
    }

    /// Internal method to delete a series
    /// Used by RecurringTransactionCoordinator
    func deleteRecurringSeriesInternal(_ seriesId: String, deleteTransactions: Bool) {
        recurringOccurrences = recurringOccurrences.filter { $0.seriesId != seriesId }
        recurringSeries = recurringSeries.filter { $0.id != seriesId }

        saveRecurringSeries()
        repository.saveRecurringOccurrences(recurringOccurrences)
    }

    /// Internal method to pause a subscription
    /// Used by RecurringTransactionCoordinator
    func pauseSubscriptionInternal(_ subscriptionId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == subscriptionId && $0.isSubscription }) {
            var newSeries = recurringSeries
            newSeries[index].status = .paused
            newSeries[index].isActive = false
            recurringSeries = newSeries
            saveRecurringSeries()
        }
    }

    /// Internal method to resume a subscription
    /// Used by RecurringTransactionCoordinator
    func resumeSubscriptionInternal(_ subscriptionId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == subscriptionId && $0.isSubscription }) {
            var newSeries = recurringSeries
            newSeries[index].status = .active
            newSeries[index].isActive = true
            recurringSeries = newSeries
            saveRecurringSeries()
        }
    }

    /// Internal method to archive a subscription
    /// Used by RecurringTransactionCoordinator
    func archiveSubscriptionInternal(_ subscriptionId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == subscriptionId && $0.isSubscription }) {
            var newSeries = recurringSeries
            newSeries[index].status = .archived
            newSeries[index].isActive = false
            recurringSeries = newSeries
            saveRecurringSeries()
        }
    }

    // MARK: - Planned Transactions (for SubscriptionDetailView)

    /// Get planned transactions for a subscription (past + future)
    /// REFACTORED 2026-02-02: Extracted from SubscriptionDetailView to eliminate 110 LOC duplication
    /// - Parameters:
    ///   - subscriptionId: The subscription ID
    ///   - horizonMonths: Number of months ahead to generate (default: 3)
    /// - Returns: Array of planned transactions sorted by date descending
    func getPlannedTransactions(for subscriptionId: String, horizonMonths: Int = 3) -> [Transaction] {
        guard let subscription = recurringSeries.first(where: { $0.id == subscriptionId }) else {
            return []
        }

        let dateFormatter = DateFormatters.dateFormatter
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let startDate = dateFormatter.date(from: subscription.startDate) else {
            return []
        }

        guard let horizonDate = calendar.date(byAdding: .month, value: horizonMonths, to: today) else {
            return []
        }

        var transactions: [Transaction] = []
        var currentDate = startDate
        let maxIterations = calculateMaxIterations(frequency: subscription.frequency, horizonMonths: horizonMonths)
        var iterationCount = 0

        while currentDate <= horizonDate && iterationCount < maxIterations {
            iterationCount += 1

            let dateString = dateFormatter.string(from: currentDate)
            let amountDouble = NSDecimalNumber(decimal: subscription.amount).doubleValue
            let createdAt = dateFormatter.date(from: dateString)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970

            let transactionId = TransactionIDGenerator.generateID(
                date: dateString,
                description: subscription.description,
                amount: amountDouble,
                type: .expense,
                currency: subscription.currency,
                createdAt: createdAt
            )

            let transaction = Transaction(
                id: transactionId,
                date: dateString,
                description: subscription.description,
                amount: amountDouble,
                currency: subscription.currency,
                convertedAmount: nil,
                type: .expense,
                category: subscription.category,
                subcategory: subscription.subcategory,
                accountId: subscription.accountId,
                targetAccountId: nil,
                accountName: nil,
                targetAccountName: nil,
                recurringSeriesId: subscription.id,
                recurringOccurrenceId: nil,
                createdAt: createdAt
            )

            transactions.append(transaction)

            guard let nextDate = calculateNextDate(from: currentDate, frequency: subscription.frequency) else {
                break
            }

            if nextDate <= currentDate {
                break
            }

            currentDate = nextDate
        }

        return transactions.sorted { $0.date > $1.date }
    }

    /// Calculate next date based on frequency
    private func calculateNextDate(from date: Date, frequency: RecurringFrequency) -> Date? {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    /// Calculate max iterations to prevent infinite loops
    private func calculateMaxIterations(frequency: RecurringFrequency, horizonMonths: Int) -> Int {
        switch frequency {
        case .daily:
            return min(horizonMonths * 30 + 10, 10000)
        case .weekly:
            return min(horizonMonths * 4 + 10, 2000)
        case .monthly:
            return min(horizonMonths + 10, 500)
        case .yearly:
            return min(horizonMonths / 12 + 10, 100)
        }
    }

    // MARK: - Currency Conversion Helpers

    /// Вычисляет суммарный объём активных подписок в указанной валюте.
    /// Извлечён из SubscriptionsCardView для соблюдения SRP.
    func calculateTotalInCurrency(_ baseCurrency: String) async -> (total: Decimal, isComplete: Bool) {
        guard !activeSubscriptions.isEmpty else {
            return (0, true)
        }

        var total: Decimal = 0

        for subscription in activeSubscriptions {
            if subscription.currency == baseCurrency {
                total += subscription.amount
            } else {
                let amountDouble = NSDecimalNumber(decimal: subscription.amount).doubleValue
                if let converted = await CurrencyConverter.convert(
                    amount: amountDouble,
                    from: subscription.currency,
                    to: baseCurrency
                ) {
                    total += Decimal(converted)
                } else {
                    total += subscription.amount
                }
            }
        }

        return (total, true)
    }
}
