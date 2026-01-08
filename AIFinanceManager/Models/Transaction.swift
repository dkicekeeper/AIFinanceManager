//
//  Transaction.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

enum TransactionType: String, Codable {
    case income
    case expense
    case internalTransfer = "internal"
}

struct Transaction: Identifiable, Codable, Equatable {
    let id: String
    let date: String // YYYY-MM-DD
    let time: String? // HH:mm
    let description: String
    let amount: Double
    let currency: String
    let type: TransactionType
    let category: String
    let subcategory: String?
    let accountId: String?
    let targetAccountId: String?
    let recurringSeriesId: String? // Связь с периодической серией
    let recurringOccurrenceId: String? // Связь с конкретным occurrence
    
    init(
        id: String,
        date: String,
        time: String? = nil,
        description: String,
        amount: Double,
        currency: String,
        type: TransactionType,
        category: String,
        subcategory: String? = nil,
        accountId: String? = nil,
        targetAccountId: String? = nil,
        recurringSeriesId: String? = nil,
        recurringOccurrenceId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.description = description
        self.amount = amount
        self.currency = currency
        self.type = type
        self.category = category
        self.subcategory = subcategory
        self.accountId = accountId
        self.targetAccountId = targetAccountId
        self.recurringSeriesId = recurringSeriesId
        self.recurringOccurrenceId = recurringOccurrenceId
    }
}

struct CategoryRule: Codable, Equatable {
    let description: String
    let category: String
    let subcategory: String?
}

struct AnalysisResult: Codable {
    let transactions: [Transaction]
    let summary: Summary
}

struct Summary: Codable {
    let totalIncome: Double
    let totalExpenses: Double
    let totalInternalTransfers: Double
    let netFlow: Double
    let currency: String
    let startDate: String
    let endDate: String
    let plannedAmount: Double // Сумма всех невыполненных recurring операций
}

struct Account: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var balance: Double
    var currency: String
    
    init(id: String = UUID().uuidString, name: String, balance: Double, currency: String) {
        self.id = id
        self.name = name
        self.balance = balance
        self.currency = currency
    }
}
