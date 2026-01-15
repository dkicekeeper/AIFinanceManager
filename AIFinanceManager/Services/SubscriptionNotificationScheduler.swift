//
//  SubscriptionNotificationScheduler.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import UserNotifications
import Combine

@MainActor
class SubscriptionNotificationScheduler {
    static let shared = SubscriptionNotificationScheduler()
    
    private init() {}
    
    /// ID scheme: "subscription_\(seriesId)_\(offsetDays)"
    private func notificationId(for seriesId: String, offsetDays: Int) -> String {
        return "subscription_\(seriesId)_\(offsetDays)"
    }
    
    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    /// Schedule notifications for a subscription
    func scheduleNotifications(for series: RecurringSeries, nextChargeDate: Date) async {
        guard series.isSubscription,
              series.subscriptionStatus == .active,
              let reminderOffsets = series.reminderOffsets,
              !reminderOffsets.isEmpty else {
            return
        }
        
        // First, cancel existing notifications for this subscription
        await cancelNotifications(for: series.id)
        
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        
        // Format amount and currency
        let amountString = Formatting.formatCurrency(
            NSDecimalNumber(decimal: series.amount).doubleValue,
            currency: series.currency
        )
        
        // Create notifications for each reminder offset
        var requests: [UNNotificationRequest] = []
        for offsetDays in reminderOffsets {
            guard offsetDays > 0 else { continue }
            
            // Calculate notification date: nextChargeDate - offsetDays
            guard let notificationDate = calendar.date(byAdding: .day, value: -offsetDays, to: nextChargeDate),
                  notificationDate > Date() else {
                // Skip if notification date is in the past
                continue
            }
            
            // Create date components for the notification
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = "Напоминание о подписке"
            content.body = "Подписка \"\(series.description)\" будет списана \(amountString) через \(offsetDays) \(dayWord(offsetDays))"
            content.sound = .default
            content.badge = NSNumber(value: 1)
            
            // Create notification request
            let identifier = notificationId(for: series.id, offsetDays: offsetDays)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            requests.append(request)
        }
        
        // Add all notifications
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    /// Cancel all notifications for a subscription
    func cancelNotifications(for seriesId: String) async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        // Find all notification IDs that match this subscription
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("subscription_\(seriesId)_") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }
    
    /// Cancel all subscription notifications (cleanup)
    func cancelAllSubscriptionNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("subscription_") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }
    
    /// Helper: get Russian word for days
    private func dayWord(_ days: Int) -> String {
        let lastDigit = days % 10
        let lastTwoDigits = days % 100
        
        if lastTwoDigits >= 11 && lastTwoDigits <= 19 {
            return "дней"
        }
        
        switch lastDigit {
        case 1:
            return "день"
        case 2, 3, 4:
            return "дня"
        default:
            return "дней"
        }
    }
    
    /// Calculate next charge date for a subscription
    func calculateNextChargeDate(for series: RecurringSeries) -> Date? {
        guard series.isSubscription,
              series.subscriptionStatus == .active else {
            return nil
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatters.dateFormatter
        
        guard let startDate = dateFormatter.date(from: series.startDate) else {
            return nil
        }
        
        // If startDate is in the future, return it
        if startDate > today {
            return startDate
        }
        
        // Calculate next occurrence based on frequency
        let nextDate: Date?
        switch series.frequency {
        case .daily:
            nextDate = calendar.date(byAdding: .day, value: 1, to: today)
        case .weekly:
            nextDate = calendar.date(byAdding: .day, value: 7, to: today)
        case .monthly:
            nextDate = calendar.date(byAdding: .month, value: 1, to: today)
        case .yearly:
            nextDate = calendar.date(byAdding: .year, value: 1, to: today)
        }
        
        return nextDate
    }
}
