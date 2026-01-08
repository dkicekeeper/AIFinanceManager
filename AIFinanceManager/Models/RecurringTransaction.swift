//
//  RecurringTransaction.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct RecurringSeries: Identifiable, Codable, Equatable {
    let id: String
    var isActive: Bool
    var amount: Decimal
    var currency: String
    var category: String
    var subcategory: String?
    var description: String
    var accountId: String?
    var targetAccountId: String?
    var frequency: RecurringFrequency
    var startDate: String // YYYY-MM-DD
    var lastGeneratedDate: String? // YYYY-MM-DD
    
    init(
        id: String = UUID().uuidString,
        isActive: Bool = true,
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String? = nil,
        description: String,
        accountId: String? = nil,
        targetAccountId: String? = nil,
        frequency: RecurringFrequency,
        startDate: String,
        lastGeneratedDate: String? = nil
    ) {
        self.id = id
        self.isActive = isActive
        self.amount = amount
        self.currency = currency
        self.category = category
        self.subcategory = subcategory
        self.description = description
        self.accountId = accountId
        self.targetAccountId = targetAccountId
        self.frequency = frequency
        self.startDate = startDate
        self.lastGeneratedDate = lastGeneratedDate
    }
}

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    
    var displayName: String {
        switch self {
        case .daily: return NSLocalizedString("Daily", comment: "")
        case .weekly: return NSLocalizedString("Weekly", comment: "")
        case .monthly: return NSLocalizedString("Monthly", comment: "")
        case .yearly: return NSLocalizedString("Yearly", comment: "")
        }
    }
}

struct RecurringOccurrence: Identifiable, Codable, Equatable {
    let id: String
    let seriesId: String
    let occurrenceDate: String // YYYY-MM-DD
    let transactionId: String
    
    init(
        id: String = UUID().uuidString,
        seriesId: String,
        occurrenceDate: String,
        transactionId: String
    ) {
        self.id = id
        self.seriesId = seriesId
        self.occurrenceDate = occurrenceDate
        self.transactionId = transactionId
    }
}
