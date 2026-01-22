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
        recurringSeries.append(series)
        repository.saveRecurringSeries(recurringSeries)
        return series
    }
    
    func updateRecurringSeries(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]

            // Если изменилась частота, нужно удалить все будущие транзакции и перегенерировать
            let _ = oldSeries.frequency != series.frequency
            let _ = oldSeries.startDate != series.startDate

            // Создаем новый массив вместо модификации элемента на месте
            var newSeries = recurringSeries
            newSeries[index] = series

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            objectWillChange.send()

            // Note: Deleting future transactions should be handled by TransactionsViewModel
            // This method only updates the series

            repository.saveRecurringSeries(recurringSeries)
        }
    }
    
    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            // Создаем новый массив и модифицируем элемент
            var newSeries = recurringSeries
            newSeries[index].isActive = false

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            objectWillChange.send()

            repository.saveRecurringSeries(recurringSeries)
        }
    }
    
    func deleteRecurringSeries(_ seriesId: String) {
        // Удаляем все occurrences
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        // Удаляем серию
        recurringSeries.removeAll { $0.id == seriesId }
        repository.saveRecurringSeries(recurringSeries)
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
        recurringSeries.append(series)
        repository.saveRecurringSeries(recurringSeries)
        
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

            // If frequency or start date changed, remove future transactions
            let _ = oldSeries.frequency != series.frequency
            let _ = oldSeries.startDate != series.startDate

            // Создаем новый массив вместо модификации элемента на месте
            var newSeries = recurringSeries
            newSeries[index] = series

            // Переприсваиваем весь массив для триггера @Published
            recurringSeries = newSeries
            objectWillChange.send()

            // Note: Future transaction deletion should be handled by TransactionsViewModel

            repository.saveRecurringSeries(recurringSeries)
            
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
            objectWillChange.send()

            repository.saveRecurringSeries(recurringSeries)

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
            objectWillChange.send()

            repository.saveRecurringSeries(recurringSeries)

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
            objectWillChange.send()

            repository.saveRecurringSeries(recurringSeries)

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
}
