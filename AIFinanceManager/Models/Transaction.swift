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
    let amount: Double // Основная сумма операции
    let currency: String // Валюта операции
    let convertedAmount: Double? // Конвертированная сумма в валюте счета
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
        description: String,
        amount: Double,
        currency: String,
        convertedAmount: Double? = nil,
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
        self.description = description
        self.amount = amount
        self.currency = currency
        self.convertedAmount = convertedAmount
        self.type = type
        self.category = category
        self.subcategory = subcategory
        self.accountId = accountId
        self.targetAccountId = targetAccountId
        self.recurringSeriesId = recurringSeriesId
        self.recurringOccurrenceId = recurringOccurrenceId
    }
    
    // Кастомный decoder для обратной совместимости
    enum CodingKeys: String, CodingKey {
        case id, date, time, description, amount, currency, convertedAmount, type, category, subcategory
        case accountId, targetAccountId, recurringSeriesId, recurringOccurrenceId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        // Игнорируем поле time для обратной совместимости
        _ = try? container.decodeIfPresent(String.self, forKey: .time)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decode(String.self, forKey: .currency)
        convertedAmount = try container.decodeIfPresent(Double.self, forKey: .convertedAmount)
        type = try container.decode(TransactionType.self, forKey: .type)
        category = try container.decode(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        targetAccountId = try container.decodeIfPresent(String.self, forKey: .targetAccountId)
        recurringSeriesId = try container.decodeIfPresent(String.self, forKey: .recurringSeriesId)
        recurringOccurrenceId = try container.decodeIfPresent(String.self, forKey: .recurringOccurrenceId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        // Не кодируем поле time, так как оно больше не существует
        try container.encode(description, forKey: .description)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(convertedAmount, forKey: .convertedAmount)
        try container.encode(type, forKey: .type)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(subcategory, forKey: .subcategory)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(targetAccountId, forKey: .targetAccountId)
        try container.encodeIfPresent(recurringSeriesId, forKey: .recurringSeriesId)
        try container.encodeIfPresent(recurringOccurrenceId, forKey: .recurringOccurrenceId)
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

struct Summary: Codable, Equatable {
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
    var bankLogo: BankLogo
    
    init(id: String = UUID().uuidString, name: String, balance: Double, currency: String, bankLogo: BankLogo = .none) {
        self.id = id
        self.name = name
        self.balance = balance
        self.currency = currency
        self.bankLogo = bankLogo
    }
    
    // Кастомный decoder для обратной совместимости со старыми данными
    enum CodingKeys: String, CodingKey {
        case id, name, balance, currency, bankLogo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        balance = try container.decode(Double.self, forKey: .balance)
        currency = try container.decode(String.self, forKey: .currency)
        // Если bankLogo отсутствует в старых данных, используем .none
        bankLogo = try container.decodeIfPresent(BankLogo.self, forKey: .bankLogo) ?? .none
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(balance, forKey: .balance)
        try container.encode(currency, forKey: .currency)
        try container.encode(bankLogo, forKey: .bankLogo)
    }
}
