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
        print("📝 [RECURRING] Created recurring series, total count: \(recurringSeries.count)")
        
        saveRecurringSeries()  // ✅ Sync save
        
        // Notify TransactionsViewModel to generate transactions for new series
        print("📢 [RECURRING] Notifying about new recurring series: \(series.id)")
        NotificationCenter.default.post(
            name: .recurringSeriesCreated,
            object: nil,
            userInfo: ["seriesId": series.id]
        )
        
        return series
    }
    
    func updateRecurringSeries(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]

            // Check if need to regenerate future transactions
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate
            let amountChanged = oldSeries.amount != series.amount
            let needsRegeneration = frequencyChanged || startDateChanged || amountChanged

            print("📝 [RECURRING] Updating series: \(series.id)")
            if needsRegeneration {
                print("🔄 [RECURRING] Changes detected - will regenerate transactions:")
                print("   Frequency: \(frequencyChanged ? "✓" : "-")")
                print("   Start Date: \(startDateChanged ? "✓" : "-")")
                print("   Amount: \(amountChanged ? "✓" : "-")")
            }

            // Создаем новый массив вместо модификации элемента на месте
            var newSeries = recurringSeries
            newSeries[index] = series

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            // NOTE: @Published automatically sends objectWillChange notification

            // Notify TransactionsViewModel to regenerate if needed
            if needsRegeneration {
                NotificationCenter.default.post(
                    name: .recurringSeriesChanged,
                    object: nil,
                    userInfo: ["seriesId": series.id, "oldSeries": oldSeries]
                )
            }

            saveRecurringSeries()  // ✅ Sync save
        }
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
    
    func deleteRecurringSeries(_ seriesId: String) {
        print("🗑️ [RECURRING] Deleting recurring series: \(seriesId)")
        
        // ✅ CRITICAL: Use filter to create new array for @Published trigger
        recurringOccurrences = recurringOccurrences.filter { $0.seriesId != seriesId }
        recurringSeries = recurringSeries.filter { $0.id != seriesId }
        
        print("📝 [RECURRING] After deletion, total count: \(recurringSeries.count)")
        
        saveRecurringSeries()  // ✅ Sync save
        repository.saveRecurringOccurrences(recurringOccurrences)
        
        // Cancel notifications for subscriptions
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }
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
        print("📝 [SUBSCRIPTION] Created subscription, total count: \(recurringSeries.count)")
        
        saveRecurringSeries()  // ✅ Sync save
        
        // Notify TransactionsViewModel to generate transactions for new subscription
        print("📢 [SUBSCRIPTION] Notifying about new subscription: \(series.id)")
        NotificationCenter.default.post(
            name: .recurringSeriesCreated,
            object: nil,
            userInfo: ["seriesId": series.id]
        )
        
        // Schedule notifications
        Task {
            if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
            }
        }
        
        return series
    }
    
    /// Update a subscription
    func updateSubscription(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]

            // Check if need to regenerate future transactions
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate
            let amountChanged = oldSeries.amount != series.amount
            let needsRegeneration = frequencyChanged || startDateChanged || amountChanged

            print("📝 [SUBSCRIPTION] Updating subscription: \(series.id)")
            if needsRegeneration {
                print("🔄 [SUBSCRIPTION] Changes detected - will regenerate transactions:")
                print("   Frequency: \(frequencyChanged ? "✓" : "-")")
                print("   Start Date: \(startDateChanged ? "✓" : "-")")
                print("   Amount: \(amountChanged ? "✓" : "-")")
            }

            // Создаем новый массив вместо модификации элемента на месте
            var newSeries = recurringSeries
            newSeries[index] = series

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            // NOTE: @Published automatically sends objectWillChange notification

            // Notify TransactionsViewModel to regenerate if needed
            if needsRegeneration {
                NotificationCenter.default.post(
                    name: .recurringSeriesChanged,
                    object: nil,
                    userInfo: ["seriesId": series.id, "oldSeries": oldSeries]
                )
            }

            saveRecurringSeries()  // ✅ Sync save (updateSubscription)
            
            // Update notifications
            Task {
                if series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                } else {
                    await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
                }
            }
        }
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
            // NOTE: @Published automatically sends objectWillChange notification

            saveRecurringSeries()  // ✅ Sync save (resumeSubscription)

            // Schedule notifications
            Task {
                if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: recurringSeries[index]) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: recurringSeries[index], nextChargeDate: nextChargeDate)
                }
            }
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
    
    /// Save recurring series
    /// Note: Uses async save through SaveCoordinator for proper Core Data handling
    /// Recurring series have complex relationships that require background context
    private func saveRecurringSeries() {
        repository.saveRecurringSeries(recurringSeries)
        print("💾 [SUBSCRIPTIONS] Saving \(recurringSeries.count) recurring series")
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
