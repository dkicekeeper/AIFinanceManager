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
    case depositTopUp = "deposit_topup"
    case depositWithdrawal = "deposit_withdrawal"
    case depositInterestAccrual = "deposit_interest"
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
    let accountName: String? // Название счета-источника (для отображения удаленных счетов)
    let targetAccountName: String? // Название счета-получателя (для отображения удаленных счетов)
    let targetCurrency: String? // Валюта счета получателя
    let targetAmount: Double? // Сумма на счете получателя (по курсу на момент транзакции)
    let recurringSeriesId: String? // Связь с периодической серией
    let recurringOccurrenceId: String? // Связь с конкретным occurrence
    let createdAt: TimeInterval // Timestamp создания транзакции для сортировки
    
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
        accountName: String? = nil,
        targetAccountName: String? = nil,
        targetCurrency: String? = nil,
        targetAmount: Double? = nil,
        recurringSeriesId: String? = nil,
        recurringOccurrenceId: String? = nil,
        createdAt: TimeInterval? = nil
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
        self.accountName = accountName
        self.targetAccountName = targetAccountName
        self.targetCurrency = targetCurrency
        self.targetAmount = targetAmount
        self.recurringSeriesId = recurringSeriesId
        self.recurringOccurrenceId = recurringOccurrenceId
        // Если createdAt не передан, используем текущее время
        self.createdAt = createdAt ?? Date().timeIntervalSince1970
    }
    
    // Кастомный decoder для обратной совместимости
    enum CodingKeys: String, CodingKey {
        case id, date, time, description, amount, currency, convertedAmount, type, category, subcategory
        case accountId, targetAccountId, accountName, targetAccountName, targetCurrency, targetAmount, recurringSeriesId, recurringOccurrenceId, createdAt
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
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        targetAccountName = try container.decodeIfPresent(String.self, forKey: .targetAccountName)
        targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency)
        targetAmount = try container.decodeIfPresent(Double.self, forKey: .targetAmount)
        recurringSeriesId = try container.decodeIfPresent(String.self, forKey: .recurringSeriesId)
        recurringOccurrenceId = try container.decodeIfPresent(String.self, forKey: .recurringOccurrenceId)
        // Для обратной совместимости: если createdAt отсутствует, используем дату транзакции
        if let existingCreatedAt = try? container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) {
            createdAt = existingCreatedAt
        } else {
            // Если createdAt отсутствует, используем дату транзакции как createdAt
            let dateFormatter = DateFormatters.dateFormatter
            if let transactionDate = dateFormatter.date(from: date) {
                createdAt = transactionDate.timeIntervalSince1970
            } else {
                // Если не удалось распарсить дату, используем текущее время
                createdAt = Date().timeIntervalSince1970
            }
        }
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
        try container.encodeIfPresent(accountName, forKey: .accountName)
        try container.encodeIfPresent(targetAccountName, forKey: .targetAccountName)
        try container.encodeIfPresent(targetCurrency, forKey: .targetCurrency)
        try container.encodeIfPresent(targetAmount, forKey: .targetAmount)
        try container.encodeIfPresent(recurringSeriesId, forKey: .recurringSeriesId)
        try container.encodeIfPresent(recurringOccurrenceId, forKey: .recurringOccurrenceId)
        try container.encode(createdAt, forKey: .createdAt)
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

// MARK: - Deposit Models

struct RateChange: Codable, Equatable {
    let effectiveFrom: String // YYYY-MM-DD
    let annualRate: Decimal
    let note: String?
    
    init(effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        self.effectiveFrom = effectiveFrom
        self.annualRate = annualRate
        self.note = note
    }
}

struct DepositInfo: Codable, Equatable {
    var bankName: String
    var principalBalance: Decimal // Тело депозита
    var capitalizationEnabled: Bool
    var interestAccruedNotCapitalized: Decimal // Начисленные, но не капитализированные проценты
    var interestRateAnnual: Decimal // Текущая годовая ставка
    var interestRateHistory: [RateChange] // История ставок
    var interestPostingDay: Int // 1-31, день месяца для начисления
    var lastInterestCalculationDate: String // YYYY-MM-DD, дата последнего расчета
    var lastInterestPostingMonth: String // YYYY-MM-01, начало месяца последнего начисления
    var interestAccruedForCurrentPeriod: Decimal // Накоплено за текущий период до начисления
    
    init(
        bankName: String,
        principalBalance: Decimal,
        capitalizationEnabled: Bool = true,
        interestAccruedNotCapitalized: Decimal = 0,
        interestRateAnnual: Decimal,
        interestRateHistory: [RateChange]? = nil,
        interestPostingDay: Int,
        lastInterestCalculationDate: String? = nil,
        lastInterestPostingMonth: String? = nil,
        interestAccruedForCurrentPeriod: Decimal = 0
    ) {
        self.bankName = bankName
        self.principalBalance = principalBalance
        self.capitalizationEnabled = capitalizationEnabled
        self.interestAccruedNotCapitalized = interestAccruedNotCapitalized
        self.interestRateAnnual = interestRateAnnual
        self.interestRateHistory = interestRateHistory ?? [RateChange(
            effectiveFrom: lastInterestCalculationDate ?? DateFormatters.dateFormatter.string(from: Date()),
            annualRate: interestRateAnnual
        )]
        self.interestPostingDay = interestPostingDay
        let today = DateFormatters.dateFormatter.string(from: Date())
        self.lastInterestCalculationDate = lastInterestCalculationDate ?? today
        if let lastMonth = lastInterestPostingMonth {
            self.lastInterestPostingMonth = lastMonth
        } else {
            // По умолчанию - начало текущего месяца
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: Date())
            if let date = calendar.date(from: components) {
                self.lastInterestPostingMonth = DateFormatters.dateFormatter.string(from: date)
            } else {
                self.lastInterestPostingMonth = today
            }
        }
        self.interestAccruedForCurrentPeriod = interestAccruedForCurrentPeriod
    }
}

struct Account: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var balance: Double  // DEPRECATED - use BalanceCoordinator.balances instead
    var currency: String
    var bankLogo: BankLogo
    var depositInfo: DepositInfo? // Опциональная информация о депозите (nil для обычных счетов)
    var createdDate: Date?
    var shouldCalculateFromTransactions: Bool // Режим расчета баланса: true = из транзакций, false = manual
    var initialBalance: Double?  // Начальный баланс для manual счетов (nil для shouldCalculateFromTransactions=true)

    init(id: String = UUID().uuidString, name: String, balance: Double, currency: String, bankLogo: BankLogo = .none, depositInfo: DepositInfo? = nil, createdDate: Date? = nil, shouldCalculateFromTransactions: Bool = false, initialBalance: Double? = nil) {
        self.id = id
        self.name = name
        self.balance = balance
        self.currency = currency
        self.bankLogo = bankLogo
        self.depositInfo = depositInfo
        self.createdDate = createdDate ?? Date()
        self.shouldCalculateFromTransactions = shouldCalculateFromTransactions
        // Если initialBalance не указан, используем balance
        self.initialBalance = initialBalance ?? (shouldCalculateFromTransactions ? 0.0 : balance)
    }

    // Кастомный decoder для обратной совместимости со старыми данными
    enum CodingKeys: String, CodingKey {
        case id, name, balance, currency, bankLogo, depositInfo, createdDate, shouldCalculateFromTransactions, initialBalance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        balance = try container.decode(Double.self, forKey: .balance)
        currency = try container.decode(String.self, forKey: .currency)
        bankLogo = try container.decodeIfPresent(BankLogo.self, forKey: .bankLogo) ?? .none
        depositInfo = try container.decodeIfPresent(DepositInfo.self, forKey: .depositInfo)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate)
        // Для обратной совместимости: если поля нет, используем false (manual mode)
        shouldCalculateFromTransactions = try container.decodeIfPresent(Bool.self, forKey: .shouldCalculateFromTransactions) ?? false

        // Для обратной совместимости: если initialBalance не сохранен, берем из balance
        if let savedInitialBalance = try container.decodeIfPresent(Double.self, forKey: .initialBalance) {
            initialBalance = savedInitialBalance
        } else {
            // Старые данные: используем balance как initialBalance
            initialBalance = shouldCalculateFromTransactions ? 0.0 : balance
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(balance, forKey: .balance)
        try container.encode(currency, forKey: .currency)
        try container.encode(bankLogo, forKey: .bankLogo)
        try container.encodeIfPresent(depositInfo, forKey: .depositInfo)
        try container.encodeIfPresent(createdDate, forKey: .createdDate)
        try container.encode(shouldCalculateFromTransactions, forKey: .shouldCalculateFromTransactions)
        try container.encodeIfPresent(initialBalance, forKey: .initialBalance)
    }
    
    // Computed property для проверки, является ли счет депозитом
    var isDeposit: Bool {
        depositInfo != nil
    }
}
