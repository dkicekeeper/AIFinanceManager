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
    let description: String
    let amount: Double
    let currency: String
    let type: TransactionType
    let category: String
    let subcategory: String?
    
    init(id: String, date: String, description: String, amount: Double, currency: String, type: TransactionType, category: String, subcategory: String? = nil) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
        self.currency = currency
        self.type = type
        self.category = category
        self.subcategory = subcategory
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
}
