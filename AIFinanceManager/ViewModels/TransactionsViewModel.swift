//
//  TransactionsViewModel.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var accounts: [Account] = []
    @Published var customCategories: [CustomCategory] = []
    @Published var recurringSeries: [RecurringSeries] = []
    @Published var recurringOccurrences: [RecurringOccurrence] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    @Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []
    @Published var selectedCategories: Set<String>? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currencyConversionWarning: String? = nil
    @Published var appSettings: AppSettings = AppSettings.load()

    private var initialAccountBalances: [String: Double] = [:]
    private var cachedSummary: Summary?
    private var summaryCacheInvalidated = true
    private var cachedCategoryExpenses: [String: CategoryExpense]?
    private var categoryExpensesCacheInvalidated = true

    // Currency conversion cache: "txId_baseCurrency" -> converted amount
    private var convertedAmountsCache: [String: Double] = [:]
    private var conversionCacheInvalidated = true

    // Transaction indexes for fast filtering
    private let indexManager = TransactionIndexManager()

    func invalidateCaches() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
        conversionCacheInvalidated = true
        indexManager.invalidate()
    }

    // MARK: - Dependencies

    weak var accountsViewModel: AccountsViewModel?

    // MARK: - Repository

    let repository: DataRepositoryProtocol

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        print("🏗️ [INIT] Initializing TransactionsViewModel (deferred loading)")
        // Don't load data synchronously in init - use loadDataAsync() instead
    }
    
    private var isDataLoaded = false
    
    /// Load all data asynchronously for better app startup performance
    func loadDataAsync() async {
        // Prevent double loading
        guard !isDataLoaded else {
            print("⏭️ [ASYNC_LOAD] Data already loaded, skipping")
            return
        }
        
        isDataLoaded = true
        print("📂 [ASYNC_LOAD] Starting async data load")
        PerformanceProfiler.start("TransactionsViewModel.loadDataAsync")
        
        await MainActor.run {
            isLoading = true
        }
        
        // Load data in background thread
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.loadFromStorage()
            }
        }.value
        
        // Generate recurring transactions (limited horizon)
        // Note: PerformanceProfiler is handled inside the method itself
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                self.generateRecurringTransactions()
            }
        }.value
        
        await MainActor.run {
            isLoading = false
        }
        
        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
        print("✅ [ASYNC_LOAD] Async data load complete")
    }
    
    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }
    
    var filteredTransactions: [Transaction] {
        var transactions = applyRules(to: allTransactions)
        
        if let selectedCategories = selectedCategories {
            transactions = transactions.filter { transaction in
                selectedCategories.contains(transaction.category)
            }
        }
        
        return filterRecurringTransactions(transactions)
    }
    
    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        let transactions = applyRules(to: allTransactions)
        return transactions.filter { transaction in
            guard let transactionDate = Self.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= range.start && transactionDate < range.end
        }
    }
    
    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        var transactions = applyRules(to: allTransactions)
        
        if let selectedCategories = selectedCategories {
            transactions = transactions.filter { transaction in
                selectedCategories.contains(transaction.category)
            }
        }
        
        var recurringTransactions: [Transaction] = []
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]
        
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                guard let transactionDate = Self.dateFormatter.date(from: transaction.date) else {
                    continue
                }
                if transactionDate >= range.start && transactionDate < range.end {
                    regularTransactions.append(transaction)
                }
            }
        }
        
        let dateFormatter = Self.dateFormatter
        
        for series in recurringSeries where series.isActive {
            guard let seriesTransactions = recurringTransactionsBySeries[series.id] else {
                continue
            }
            
            let nextTransaction = seriesTransactions
                .compactMap { transaction -> (Transaction, Date)? in
                    guard let date = dateFormatter.date(from: transaction.date) else {
                        return nil
                    }
                    return (transaction, date)
                }
                .min(by: { $0.1 < $1.1 })
                .map { $0.0 }
            
            if let nextTransaction = nextTransaction {
                recurringTransactions.append(nextTransaction)
            }
        }
        
        return recurringTransactions + regularTransactions
    }
    
    // MARK: - History View Filtering and Grouping
    
    /// Фильтрует транзакции для HistoryView с учетом всех фильтров (время, категории, счет, поиск)
    func filterTransactionsForHistory(
        timeFilterManager: TimeFilterManager,
        accountId: String?,
        searchText: String
    ) -> [Transaction] {
        var transactions = transactionsFilteredByTimeAndCategory(timeFilterManager)
        
        if let accountId = accountId {
            transactions = transactions.filter { $0.accountId == accountId || $0.targetAccountId == accountId }
        }
        
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let searchNumber = Double(searchText.replacingOccurrences(of: ",", with: "."))
            let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            
            transactions = transactions.filter { transaction in
                if transaction.category.lowercased().contains(searchLower) {
                    return true
                }
                
                let linkedSubcategories = getSubcategoriesForTransaction(transaction.id)
                if linkedSubcategories.contains(where: { $0.name.lowercased().contains(searchLower) }) {
                    return true
                }
                
                if transaction.description.lowercased().contains(searchLower) {
                    return true
                }
                
                if let accountId = transaction.accountId,
                   let account = accountsById[accountId],
                   account.name.lowercased().contains(searchLower) {
                    return true
                }
                
                if let targetAccountId = transaction.targetAccountId,
                   let targetAccount = accountsById[targetAccountId],
                   targetAccount.name.lowercased().contains(searchLower) {
                    return true
                }
                
                let amountString = String(format: "%.2f", transaction.amount)
                if amountString.contains(searchText) || amountString.lowercased().contains(searchLower) {
                    return true
                }
                
                if let searchNum = searchNumber, abs(transaction.amount - searchNum) < 0.01 {
                    return true
                }
                
                let currency = appSettings.baseCurrency
                let formattedAmount = Formatting.formatCurrency(transaction.amount, currency: currency).lowercased()
                if formattedAmount.contains(searchLower) {
                    return true
                }
                
                return false
            }
        }
        
        return transactions
    }
    
    /// Группирует транзакции по датам и возвращает словарь с группированными транзакциями и отсортированными ключами
    func groupAndSortTransactionsByDate(_ transactions: [Transaction]) -> (grouped: [String: [Transaction]], sortedKeys: [String]) {
        var grouped: [String: [Transaction]] = [:]
        
        let calendar = Calendar.current
        let dateFormatter = Self.dateFormatter
        let displayDateFormatter = DateFormatters.displayDateFormatter
        let displayDateWithYearFormatter = DateFormatters.displayDateWithYearFormatter
        let currentYear = calendar.component(.year, from: Date())
        
        var recurringTransactions: [Transaction] = []
        var regularTransactions: [Transaction] = []
        
        for transaction in transactions {
            if transaction.recurringSeriesId != nil {
                recurringTransactions.append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }
        
        recurringTransactions.sort { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 < date2
        }
        
        regularTransactions.sort { tx1, tx2 in
            if tx1.createdAt != tx2.createdAt {
                return tx1.createdAt > tx2.createdAt
            }
            return tx1.id > tx2.id
        }
        
        let allTransactions = recurringTransactions + regularTransactions
        
        for transaction in allTransactions {
            guard let date = dateFormatter.date(from: transaction.date) else { continue }
            
            let dateKey: String
            let today = calendar.startOfDay(for: Date())
            let transactionDay = calendar.startOfDay(for: date)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let transactionYear = calendar.component(.year, from: date)
            
            if transactionDay == today {
                dateKey = "Сегодня"
            } else if transactionDay == yesterday {
                dateKey = "Вчера"
            } else {
                if transactionYear != currentYear {
                    dateKey = displayDateWithYearFormatter.string(from: date)
                } else {
                    dateKey = displayDateFormatter.string(from: date)
                }
            }
            
            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(transaction)
        }
        
        for key in grouped.keys {
            let today = calendar.startOfDay(for: Date())
            
            grouped[key]?.sort { tx1, tx2 in
                let isRecurring1 = tx1.recurringSeriesId != nil
                let isRecurring2 = tx2.recurringSeriesId != nil
                
                if isRecurring1 && isRecurring2 {
                    guard let date1 = dateFormatter.date(from: tx1.date),
                          let date2 = dateFormatter.date(from: tx2.date) else {
                        return false
                    }
                    if date1 > today && date2 > today {
                        return date1 > date2
                    } else if date1 <= today && date2 <= today {
                        return date1 < date2
                    } else {
                        return date1 > today && date2 <= today
                    }
                }
                
                if !isRecurring1 && !isRecurring2 {
                    if tx1.createdAt != tx2.createdAt {
                        return tx1.createdAt > tx2.createdAt
                    }
                    return tx1.id > tx2.id
                }
                
                return isRecurring1 && !isRecurring2
            }
        }
        
        let keys = Array(grouped.keys)
        let todayKey = keys.first { $0 == "Сегодня" }
        let yesterdayKey = keys.first { $0 == "Вчера" }
        let otherKeys = keys.filter { $0 != "Сегодня" && $0 != "Вчера" }
        
        let keysWithDates: [(key: String, date: Date, isRecurring: Bool)] = otherKeys.compactMap { key in
            guard let transactionsInGroup = grouped[key] else { return nil }
            
            if let recurringTransaction = transactionsInGroup.first(where: { $0.recurringSeriesId != nil }),
               let date = dateFormatter.date(from: recurringTransaction.date) {
                return (key: key, date: date, isRecurring: true)
            }
            
            if let firstTransaction = transactionsInGroup.first,
               let date = dateFormatter.date(from: firstTransaction.date) {
                return (key: key, date: date, isRecurring: false)
            }
            
            return nil
        }
        
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        
        let futureKeys = keysWithDates.filter { $0.date > calendar.startOfDay(for: Date()) }
            .sorted { key1, key2 in
                if key1.isRecurring && key2.isRecurring {
                    return key1.date > key2.date
                }
                if !key1.isRecurring && !key2.isRecurring {
                    return key1.date > key2.date
                }
                return key1.isRecurring && !key2.isRecurring
            }
            .map { $0.key }
        
        let pastRecurringKeys = keysWithDates.filter { $0.date < yesterdayStart && $0.isRecurring }
            .sorted { $0.date < $1.date }
            .map { $0.key }
        
        let pastRegularKeys = keysWithDates.filter { $0.date < yesterdayStart && !$0.isRecurring }
            .sorted { $0.date > $1.date }
            .map { $0.key }
        
        var sortedKeys: [String] = []
        sortedKeys.append(contentsOf: futureKeys)
        if let today = todayKey {
            sortedKeys.append(today)
        }
        if let yesterday = yesterdayKey {
            sortedKeys.append(yesterday)
        }
        sortedKeys.append(contentsOf: pastRecurringKeys)
        sortedKeys.append(contentsOf: pastRegularKeys)
        
        return (grouped, sortedKeys)
    }
    
    private func filterRecurringTransactions(_ transactions: [Transaction]) -> [Transaction] {
        let dateFormatter = Self.dateFormatter
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var result: [Transaction] = []
        var recurringSeriesShown: Set<String> = []
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]
        
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }
        
        result.append(contentsOf: regularTransactions)
        
        for series in recurringSeries where series.isActive {
            if recurringSeriesShown.contains(series.id) {
                continue
            }
            
            guard let seriesTransactions = recurringTransactionsBySeries[series.id] else {
                continue
            }
            
            let nextTransaction = seriesTransactions
                .compactMap { transaction -> (Transaction, Date)? in
                    guard let date = dateFormatter.date(from: transaction.date) else {
                        return nil
                    }
                    return (transaction, date)
                }
                .filter { $0.1 >= today }
                .min(by: { $0.1 < $1.1 })
                .map { $0.0 }
            
            if let nextTransaction = nextTransaction {
                result.append(nextTransaction)
                recurringSeriesShown.insert(series.id)
            }
        }
        
        return result.sorted { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 > date2
        }
    }
    
    func summary(timeFilterManager: TimeFilterManager) -> Summary {
        // Return cached summary if valid
        if !summaryCacheInvalidated, let cached = cachedSummary {
            return cached
        }
        
        // Compute synchronously (will be fast with indexes and caching from Phase 2)
        PerformanceProfiler.start("summary.calculation.sync")
        
        let filtered = transactionsFilteredByTime(timeFilterManager)
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        let baseCurrency = appSettings.baseCurrency
        
        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        
        for transaction in filtered {
            // Use cached conversion if available
            let amountInBaseCurrency = getConvertedAmountOrCompute(transaction: transaction, to: baseCurrency)

            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                continue
            }

            let isFutureDate = transactionDate > today

            if !isFutureDate {
                switch transaction.type {
                case .income:
                    totalIncome += amountInBaseCurrency
                case .expense:
                    totalExpenses += amountInBaseCurrency
                case .internalTransfer:
                    totalInternal += amountInBaseCurrency
                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    break
                }
            }
        }
        
        let dates = allTransactions.map { $0.date }.sorted()
        
        let result = Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            plannedAmount: 0  // Skip planned amount for now (was causing performance issues)
        )
        
        cachedSummary = result
        summaryCacheInvalidated = false
        
        PerformanceProfiler.end("summary.calculation.sync")
        return result
    }
    
    func categoryExpenses(timeFilterManager: TimeFilterManager) -> [String: CategoryExpense] {
        let filtered = transactionsFilteredByTime(timeFilterManager).filter { $0.type == .expense }
        var result: [String: CategoryExpense] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        
        for transaction in filtered {
            guard let transactionDate = dateFormatter.date(from: transaction.date),
                  transactionDate <= today else {
                continue
            }

            let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category
            let baseCurrency = appSettings.baseCurrency
            let amountInBaseCurrency: Double
            if transaction.currency == baseCurrency {
                amountInBaseCurrency = transaction.amount
            } else {
                if let converted = CurrencyConverter.convertSync(
                    amount: transaction.amount,
                    from: transaction.currency,
                    to: baseCurrency
                ) {
                    amountInBaseCurrency = converted
                } else {
                    amountInBaseCurrency = transaction.convertedAmount ?? transaction.amount
                    print("⚠️ Не удалось конвертировать транзакцию \(transaction.id) в \(baseCurrency) для categoryExpenses")
                }
            }

            var expense = result[category] ?? CategoryExpense(total: 0, subcategories: [:])
            expense.total += amountInBaseCurrency

            if let subcategory = transaction.subcategory {
                expense.subcategories[subcategory, default: 0] += amountInBaseCurrency
            }

            result[category] = expense
        }
        
        cachedCategoryExpenses = result
        categoryExpensesCacheInvalidated = false
        
        return result
    }
    
    func popularCategories(timeFilterManager: TimeFilterManager) -> [String] {
        let expenses = categoryExpenses(timeFilterManager: timeFilterManager)
        return Array(expenses.keys)
            .sorted { expenses[$0]?.total ?? 0 > expenses[$1]?.total ?? 0 }
    }
    
    var uniqueCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }
        return Array(categories).sorted()
    }
    
    var expenseCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .expense {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        return Array(categories).sorted()
    }
    
    var incomeCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .income {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        return Array(categories).sorted()
    }
    
    func addTransactions(_ newTransactions: [Transaction]) {
        let processedTransactions = newTransactions.map { transaction -> Transaction in
            let formattedDescription = formatMerchantName(transaction.description)
            let matchedCategory = matchCategory(transaction.category, type: transaction.type)
            
            return Transaction(
                id: transaction.id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        }
        
        let transactionsWithRules = applyRules(to: processedTransactions)
        let existingIDs = Set(allTransactions.map { $0.id })
        let uniqueNew = transactionsWithRules.filter { !existingIDs.contains($0.id) }
        
        if !uniqueNew.isEmpty {
            createCategoriesForTransactions(uniqueNew)
            insertTransactionsSorted(uniqueNew)
            invalidateCaches()
            rebuildIndexes()
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    /// Добавляет транзакции без сохранения и пересчета балансов (для массового импорта)
    func addTransactionsForImport(_ newTransactions: [Transaction]) {
        let processedTransactions = newTransactions.map { transaction -> Transaction in
            let formattedDescription = formatMerchantName(transaction.description)
            let matchedCategory = matchCategory(transaction.category, type: transaction.type)
            
            return Transaction(
                id: transaction.id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        }
        
        let transactionsWithRules = applyRules(to: processedTransactions)
        let existingIDs = Set(allTransactions.map { $0.id })
        let uniqueNew = transactionsWithRules.filter { !existingIDs.contains($0.id) }
        
        if !uniqueNew.isEmpty {
            createCategoriesForTransactions(uniqueNew)
            insertTransactionsSorted(uniqueNew)
            // НЕ вызываем invalidateCaches(), recalculateAccountBalances() и saveToStorage()
            // Это будет сделано в конце импорта
        }
    }
    
    private func formatMerchantName(_ description: String) -> String {
        var cleaned = description
        
        let patterns = [
            "Референс:\\s*[A-Za-z0-9]+",
            "Код авторизации:\\s*[0-9]+",
            "Референс:",
            "Код авторизации:",
            "Reference:",
            "Authorization Code:"
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            if let regex = regex {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let words = cleaned.components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }
            .map { word -> String in
                if word == word.uppercased() && word.count > 1 {
                    var result = ""
                    var isFirstChar = true
                    for char in word {
                        if char.isLetter {
                            result += isFirstChar ? char.uppercased() : char.lowercased()
                            isFirstChar = false
                        } else {
                            result += String(char)
                            if char == "." || char == "-" {
                                isFirstChar = true
                            }
                        }
                    }
                    return result
                }
                return word.capitalized
            }
        
        return words.joined(separator: " ")
    }
    
    private func matchCategory(_ categoryName: String, type: TransactionType) -> String {
        let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categoryName }
        
        if let existing = customCategories.first(where: { category in
            category.name.caseInsensitiveCompare(trimmed) == .orderedSame &&
            category.type == type
        }) {
            return existing.name
        }
        
        return trimmed
    }
    
    private func createCategoriesForTransactions(_ transactions: [Transaction]) {
        for transaction in transactions {
            guard transaction.type != .internalTransfer else { continue }
            
            let categoryName = transaction.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !categoryName.isEmpty else { continue }
            
            let existingCategory = customCategories.first { category in
                category.name.caseInsensitiveCompare(categoryName) == .orderedSame &&
                category.type == transaction.type
            }
            
            if existingCategory == nil {
                let iconName = CategoryIcon.iconName(for: categoryName, type: transaction.type, customCategories: customCategories)
                let defaultColors: [String] = [
                    "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
                    "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
                    "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
                ]
                let color = defaultColors.randomElement() ?? "#3b82f6"
                
                let newCategory = CustomCategory(
                    name: categoryName,
                    iconName: iconName,
                    colorHex: color,
                    type: transaction.type
                )
                
                customCategories.append(newCategory)
                print("✅ Создана новая категория: \(categoryName) (\(transaction.type.rawValue))")
            }
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        print("➕ [TRANSACTION] Adding transaction: \(transaction.description), amount: \(transaction.amount), type: \(transaction.type.rawValue)")
        if let accountId = transaction.accountId {
            let accountName = accounts.first(where: { $0.id == accountId })?.name ?? "Unknown"
            print("📍 [TRANSACTION] Account: \(accountName) (ID: \(accountId))")
        }

        let formattedDescription = formatMerchantName(transaction.description)
        let matchedCategory = matchCategory(transaction.category, type: transaction.type)
        
        let transactionWithID: Transaction
        if transaction.id.isEmpty {
            let id = TransactionIDGenerator.generateID(
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                type: transaction.type,
                currency: transaction.currency,
                createdAt: transaction.createdAt
            )
            transactionWithID = Transaction(
                id: id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        } else {
            transactionWithID = Transaction(
                id: transaction.id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        }
        
        let transactionsWithRules = applyRules(to: [transactionWithID])
        let existingIDs = Set(allTransactions.map { $0.id })
        
        if !existingIDs.contains(transactionWithID.id) {
            if transactionWithID.type == .internalTransfer {
                if let sourceId = transactionWithID.accountId,
                   let targetId = transactionWithID.targetAccountId {
                    let sourceIsDeposit = accounts.first(where: { $0.id == sourceId })?.isDeposit ?? false
                    let targetIsDeposit = accounts.first(where: { $0.id == targetId })?.isDeposit ?? false
                    
                    if sourceIsDeposit || targetIsDeposit {
                        updateDepositBalancesForTransfer(
                            transaction: transactionWithID,
                            sourceId: sourceId,
                            targetId: targetId
                        )
                    }
                }
            }
            
            createCategoriesForTransactions(transactionsWithRules)
            insertTransactionsSorted(transactionsWithRules)
            print("🔄 [TRANSACTION] Invalidating caches and recalculating balances")
            invalidateCaches()
            recalculateAccountBalances()
            print("💾 [TRANSACTION] Saving to storage")
            saveToStorage()
            print("✅ [TRANSACTION] Transaction added successfully")
        } else {
            print("⚠️ [TRANSACTION] Transaction with ID \(transactionWithID.id) already exists, skipping")
        }
    }
    
    /// ⚠️ DEPRECATED: This method modifies accounts in-place but changes are overwritten by recalculateAccountBalances()
    /// Consider refactoring to avoid redundant calculations
    private func updateDepositBalancesForTransfer(transaction: Transaction, sourceId: String, targetId: String) {
        guard let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = accounts.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        
        let sourceAccount = accounts[sourceIndex]
        let targetAccount = accounts[targetIndex]
        
        let sourceAmount: Double = {
            if transaction.currency == sourceAccount.currency {
                return transaction.amount
            } else if let convertedAmount = transaction.convertedAmount, transaction.currency == sourceAccount.currency {
                return convertedAmount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: sourceAccount.currency
            ) {
                return converted
            } else {
                return transaction.amount
            }
        }()
        
        let targetAmount: Double = {
            if transaction.currency == targetAccount.currency {
                return transaction.amount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: targetAccount.currency
            ) {
                return converted
            } else {
                return transaction.amount
            }
        }()
        
        if var sourceDepositInfo = sourceAccount.depositInfo {
            let amountDecimal = Decimal(sourceAmount)
            if !sourceDepositInfo.capitalizationEnabled && sourceDepositInfo.interestAccruedNotCapitalized > 0 {
                if amountDecimal <= sourceDepositInfo.interestAccruedNotCapitalized {
                    sourceDepositInfo.interestAccruedNotCapitalized -= amountDecimal
                } else {
                    let remaining = amountDecimal - sourceDepositInfo.interestAccruedNotCapitalized
                    sourceDepositInfo.interestAccruedNotCapitalized = 0
                    sourceDepositInfo.principalBalance -= remaining
                }
            } else {
                sourceDepositInfo.principalBalance -= amountDecimal
            }
            accounts[sourceIndex].depositInfo = sourceDepositInfo
            var totalBalance: Decimal = sourceDepositInfo.principalBalance
            if !sourceDepositInfo.capitalizationEnabled {
                totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
            }
            accounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            accounts[sourceIndex].balance -= sourceAmount
        }
        
        if var targetDepositInfo = targetAccount.depositInfo {
            let amountDecimal = Decimal(targetAmount)
            targetDepositInfo.principalBalance += amountDecimal
            accounts[targetIndex].depositInfo = targetDepositInfo
            var totalBalance: Decimal = targetDepositInfo.principalBalance
            if !targetDepositInfo.capitalizationEnabled {
                totalBalance += targetDepositInfo.interestAccruedNotCapitalized
            }
            accounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            accounts[targetIndex].balance += targetAmount
        }
    }
    
    func updateTransactionCategory(_ transactionId: String, category: String, subcategory: String?) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transactionId }) else {
            return
        }
        
        let transaction = allTransactions[index]
        
        let newRule = CategoryRule(
            description: transaction.description,
            category: category,
            subcategory: subcategory
        )
        
        categoryRules.removeAll { $0.description.lowercased() == newRule.description.lowercased() }
        categoryRules.append(newRule)
        
        for i in allTransactions.indices {
            if allTransactions[i].description.lowercased() == newRule.description.lowercased() {
                allTransactions[i] = Transaction(
                    id: allTransactions[i].id,
                    date: allTransactions[i].date,
                    description: allTransactions[i].description,
                    amount: allTransactions[i].amount,
                    currency: allTransactions[i].currency,
                    convertedAmount: allTransactions[i].convertedAmount,
                    type: allTransactions[i].type,
                    category: category,
                    subcategory: subcategory,
                    accountId: allTransactions[i].accountId,
                    targetAccountId: allTransactions[i].targetAccountId,
                    recurringSeriesId: allTransactions[i].recurringSeriesId,
                    recurringOccurrenceId: allTransactions[i].recurringOccurrenceId,
                    createdAt: allTransactions[i].createdAt
                )
            }
        }
        
        invalidateCaches()
        saveToStorage()
    }
    
    func clearHistory() {
        allTransactions = []
        categoryRules = []
        accounts = []
        saveToStorage()
    }
    
    func resetAllData() {
        allTransactions = []
        categoryRules = []
        accounts = []
        customCategories = []
        recurringSeries = []
        recurringOccurrences = []
        subcategories = []
        categorySubcategoryLinks = []
        transactionSubcategoryLinks = []
        initialAccountBalances = [:]
        selectedCategories = nil
        invalidateCaches()
        repository.clearAllData()
        
        // Принудительно уведомляем об изменении для обновления UI
        objectWillChange.send()
        
        print("✅ Все данные приложения обнулены")
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        print("🗑️ [TRANSACTION] Deleting transaction: \(transaction.description), amount: \(transaction.amount)")

        // removeAll уже создает новый массив, что правильно триггерит @Published
        allTransactions.removeAll { $0.id == transaction.id }
        print("📢 [TRANSACTION] allTransactions updated after delete, count: \(allTransactions.count)")

        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        print("🔄 [TRANSACTION] Recalculating balances after delete")
        invalidateCaches()
        recalculateAccountBalances()
        saveToStorage()
    }

    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }

        print("✏️ [TRANSACTION] Updating transaction: \(transaction.description), amount: \(transaction.amount)")

        // Создаем новый массив вместо модификации элемента на месте
        var newTransactions = allTransactions
        newTransactions[index] = transaction

        // Переприсваиваем весь массив для триггера @Published
        print("📢 [TRANSACTION] Reassigning allTransactions array to trigger @Published")
        allTransactions = newTransactions

        invalidateCaches()
        recalculateAccountBalances()
        saveToStorage()
    }

    // MARK: - Custom Categories
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.addCategory instead
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.updateCategory instead
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.deleteCategory instead
    
    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    // MARK: - Accounts

    /// ⚠️ DEPRECATED: Use AccountsViewModel.addAccount instead

    /// ⚠️ DEPRECATED: Use AccountsViewModel.updateAccount instead
    
    /// ⚠️ DEPRECATED: Use AccountsViewModel.deleteAccount instead

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }

        let currency = accounts[sourceIndex].currency
        
        // CRITICAL: Создаем новый массив вместо модификации на месте
        // Это необходимо для корректной работы @Published property wrapper
        var newAccounts = accounts

        newAccounts[sourceIndex].balance -= amount
        
        if var sourceDepositInfo = newAccounts[sourceIndex].depositInfo {
            let amountDecimal = Decimal(amount)
            if !sourceDepositInfo.capitalizationEnabled && sourceDepositInfo.interestAccruedNotCapitalized > 0 {
                if amountDecimal <= sourceDepositInfo.interestAccruedNotCapitalized {
                    sourceDepositInfo.interestAccruedNotCapitalized -= amountDecimal
                } else {
                    let remaining = amountDecimal - sourceDepositInfo.interestAccruedNotCapitalized
                    sourceDepositInfo.interestAccruedNotCapitalized = 0
                    sourceDepositInfo.principalBalance -= remaining
                }
            } else {
                sourceDepositInfo.principalBalance -= amountDecimal
            }
            newAccounts[sourceIndex].depositInfo = sourceDepositInfo
            var totalBalance: Decimal = sourceDepositInfo.principalBalance
            if !sourceDepositInfo.capitalizationEnabled {
                totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
            }
            newAccounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        }
        
        let targetAccount = newAccounts[targetIndex]
        let targetAmount: Double
        if currency == targetAccount.currency {
            targetAmount = amount
        } else if let converted = CurrencyConverter.convertSync(
            amount: amount,
            from: currency,
            to: targetAccount.currency
        ) {
            targetAmount = converted
        } else {
            print("⚠️ Не удалось конвертировать \(amount) \(currency) в \(targetAccount.currency) для депозита-получателя")
            targetAmount = amount
        }
        
        if var targetDepositInfo = targetAccount.depositInfo {
            let amountDecimal = Decimal(targetAmount)
            targetDepositInfo.principalBalance += amountDecimal
            newAccounts[targetIndex].depositInfo = targetDepositInfo
            var totalBalance: Decimal = targetDepositInfo.principalBalance
            if !targetDepositInfo.capitalizationEnabled {
                totalBalance += targetDepositInfo.interestAccruedNotCapitalized
            }
            newAccounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            newAccounts[targetIndex].balance += targetAmount
        }
        
        // Переприсваиваем весь массив для триггера @Published
        print("📢 [TRANSFER] Reassigning accounts array to trigger @Published")
        print("💰 [TRANSFER] Source '\(newAccounts[sourceIndex].name)': balance = \(newAccounts[sourceIndex].balance)")
        print("💰 [TRANSFER] Target '\(newAccounts[targetIndex].name)': balance = \(newAccounts[targetIndex].balance)")
        accounts = newAccounts

        let createdAt = Date().timeIntervalSince1970
        let id = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .internalTransfer,
            currency: currency,
            createdAt: createdAt
        )

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Перевод",
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )

        insertTransactionsSorted([transferTx])
        
        // CRITICAL: Синхронизируем обновленные балансы с AccountsViewModel
        // Без этого UI не обновится, т.к. карточки счетов используют accountsViewModel.accounts
        if let accountsVM = accountsViewModel {
            print("🔗 [TRANSFER] Syncing balances with AccountsViewModel")
            accountsVM.syncAccountBalances(accounts)
        } else {
            print("⚠️ [TRANSFER] AccountsViewModel is nil, skipping balance sync")
        }
        
        saveToStorage()
    }
    
    // MARK: - Deposits
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.addDeposit instead
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.updateDeposit instead
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.deleteDeposit instead
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.addDepositRateChange instead
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.reconcileAllDeposits instead
    
    // MARK: - Helper Methods

    private func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        guard !newTransactions.isEmpty else { return }

        print("📝 [TRANSACTION] Inserting \(newTransactions.count) transactions into allTransactions")

        let sortedNew = newTransactions.sorted { $0.date > $1.date }

        if allTransactions.isEmpty {
            print("📝 [TRANSACTION] allTransactions is empty, setting to new transactions")
            allTransactions = sortedNew
            return
        }

        // Создаем новый массив вместо модификации существующего
        // Это необходимо для корректной работы @Published property wrapper
        var newAllTransactions = allTransactions

        for newTransaction in sortedNew {
            if let insertIndex = newAllTransactions.firstIndex(where: { $0.date <= newTransaction.date }) {
                newAllTransactions.insert(newTransaction, at: insertIndex)
            } else {
                newAllTransactions.append(newTransaction)
            }
        }

        // Переприсваиваем весь массив для триггера @Published
        print("📢 [TRANSACTION] Reassigning allTransactions array to trigger @Published")
        allTransactions = newAllTransactions
        print("✅ [TRANSACTION] allTransactions now has \(allTransactions.count) transactions")
    }

    private func applyRules(to transactions: [Transaction]) -> [Transaction] {
        guard !categoryRules.isEmpty else { return transactions }
        
        let rulesMap = Dictionary(
            uniqueKeysWithValues: categoryRules.map { ($0.description.lowercased(), $0) }
        )
        
        return transactions.map { transaction in
            if let rule = rulesMap[transaction.description.lowercased()] {
                return Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: rule.category,
                    subcategory: rule.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: transaction.recurringSeriesId,
                    recurringOccurrenceId: transaction.recurringOccurrenceId,
                    createdAt: transaction.createdAt
                )
            }
            return transaction
        }
    }
    
    func saveToStorage() {
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveToStorage")
            print("💾 [STORAGE] Starting async save in TransactionsViewModel")

            let transactions = await MainActor.run { self.allTransactions }
            let rules = await MainActor.run { self.categoryRules }
            let accs = await MainActor.run { self.accounts }
            let categories = await MainActor.run { self.customCategories }
            let series = await MainActor.run { self.recurringSeries }
            let occurrences = await MainActor.run { self.recurringOccurrences }

            print("💾 [STORAGE] Saving \(accs.count) accounts from TransactionsViewModel")
            for account in accs {
                print("   💰 '\(account.name)': balance = \(account.balance)")
            }

            // НЕ сохраняем подкатегории и связи здесь - они управляются CategoriesViewModel
            // let subcats = await MainActor.run { self.subcategories }
            // let catLinks = await MainActor.run { self.categorySubcategoryLinks }
            // let txLinks = await MainActor.run { self.transactionSubcategoryLinks }

            await MainActor.run {
                self.repository.saveTransactions(transactions)
                self.repository.saveCategoryRules(rules)
                self.repository.saveAccounts(accs)
                self.repository.saveCategories(categories)
                self.repository.saveRecurringSeries(series)
                self.repository.saveRecurringOccurrences(occurrences)
                // Подкатегории и связи сохраняются через CategoriesViewModel
                // self.repository.saveSubcategories(subcats)
                // self.repository.saveCategorySubcategoryLinks(catLinks)
                // self.repository.saveTransactionSubcategoryLinks(txLinks)
            }

            print("✅ [STORAGE] Async save completed in TransactionsViewModel")
            PerformanceProfiler.end("saveToStorage")
        }
    }

    /// Синхронная версия saveToStorage для использования при импорте
    /// Гарантирует, что все данные сохранены до возврата из функции
    func saveToStorageSync() {
        PerformanceProfiler.start("saveToStorageSync")

        // Синхронно сохраняем все данные
        saveTransactionsSync(allTransactions)
        saveCategoryRulesSync(categoryRules)
        saveAccountsSync(accounts)
        saveCategoriesSync(customCategories)
        saveRecurringSeriesSync(recurringSeries)
        saveRecurringOccurrencesSync(recurringOccurrences)
        // Подкатегории и связи сохраняются через CategoriesViewModel

        PerformanceProfiler.end("saveToStorageSync")
    }

    // MARK: - Синхронные методы сохранения для импорта

    private func saveTransactionsSync(_ transactions: [Transaction]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(transactions) {
            UserDefaults.standard.set(encoded, forKey: "allTransactions")
            UserDefaults.standard.synchronize()
        }
    }

    private func saveCategoryRulesSync(_ rules: [CategoryRule]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(rules) {
            UserDefaults.standard.set(encoded, forKey: "categoryRules")
            UserDefaults.standard.synchronize()
        }
    }

    private func saveAccountsSync(_ accounts: [Account]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: "accounts")
            UserDefaults.standard.synchronize()
        }
    }

    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(categories) {
            UserDefaults.standard.set(encoded, forKey: "customCategories")
            UserDefaults.standard.synchronize()
        }
    }

    private func saveRecurringSeriesSync(_ series: [RecurringSeries]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(series) {
            UserDefaults.standard.set(encoded, forKey: "recurringSeries")
            UserDefaults.standard.synchronize()
        }
    }

    private func saveRecurringOccurrencesSync(_ occurrences: [RecurringOccurrence]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(occurrences) {
            UserDefaults.standard.set(encoded, forKey: "recurringOccurrences")
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Calculate the balance change for a specific account from all transactions
    /// This is used to determine the initial balance (starting capital) of an account
    private func calculateTransactionsBalance(for accountId: String) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        var balance: Double = 0
        
        for tx in allTransactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }
            
            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance += amountToUse
                }
            case .expense:
                if tx.accountId == accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance -= amountToUse
                }
            case .internalTransfer:
                if tx.accountId == accountId {
                    // Money leaving this account
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance -= amountToUse
                } else if tx.targetAccountId == accountId {
                    // Money coming to this account
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance += amountToUse
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Skip deposit transactions for regular accounts
                break
            }
        }
        
        return balance
    }
    
    private func loadFromStorage() {
        print("📂 [STORAGE] Loading data from storage in TransactionsViewModel")
        allTransactions = repository.loadTransactions()
        categoryRules = repository.loadCategoryRules()
        accounts = repository.loadAccounts()

        print("📊 [STORAGE] Loaded \(accounts.count) accounts in TransactionsViewModel")
        
        // CRITICAL: Calculate initial balances by subtracting all transactions from current balance
        // This ensures we have the true "starting capital" without any transactions
        for account in accounts {
            print("   💰 '\(account.name)': current balance = \(account.balance)")
            if initialAccountBalances[account.id] == nil {
                // Calculate the sum of all transactions for this account
                let transactionsSum = calculateTransactionsBalance(for: account.id)
                // Initial balance = current balance - sum of all transactions
                let initialBalance = account.balance - transactionsSum
                initialAccountBalances[account.id] = initialBalance
                print("   📝 '\(account.name)': initial balance (without transactions) = \(initialBalance), transactions sum = \(transactionsSum)")
            }
        }

        customCategories = repository.loadCategories()
        recurringSeries = repository.loadRecurringSeries()
        recurringOccurrences = repository.loadRecurringOccurrences()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        print("✅ [STORAGE] Data loaded successfully. Balances already calculated and stored.")
        // NOTE: Do NOT call recalculateAccountBalances() here!
        // Balances are already calculated and saved in Core Data.
        // Calling it again will double/triple/etc the balances on each app launch.
        // recalculateAccountBalances() should only be called after:
        // - Adding/deleting/editing transactions
        // - Importing CSV
        // - Other operations that modify transactions

        // Build indexes for fast filtering
        rebuildIndexes()

        // Precompute currency conversions in background for better UI performance
        precomputeCurrencyConversions()
    }
    
    /// Reset and recalculate all account balances from scratch
    /// This is useful when balances are corrupted (e.g., from double-counting transactions)
    /// Call this method from Settings to fix balance issues
    func resetAndRecalculateAllBalances() {
        print("🔄 [BALANCE] RESET: Starting complete balance reset and recalculation")
        
        // STEP 1: Clear all cached initial balances
        let oldInitialBalances = initialAccountBalances
        initialAccountBalances = [:]
        print("✅ [BALANCE] RESET: Cleared initial balances cache")
        
        // STEP 2: Recalculate initial balances (starting capital without any transactions)
        // Initial balance = current balance - sum of all transactions
        for account in accounts {
            let transactionsSum = calculateTransactionsBalance(for: account.id)
            let initialBalance = account.balance - transactionsSum
            initialAccountBalances[account.id] = initialBalance
            print("📝 [BALANCE] RESET: '\(account.name)': current = \(account.balance), transactions = \(transactionsSum), initial (starting capital) = \(initialBalance)")
            
            if let oldInitial = oldInitialBalances[account.id] {
                print("   🔍 Old initial balance was: \(oldInitial), difference: \(initialBalance - oldInitial)")
            }
        }
        
        // STEP 3: Recalculate current balances from scratch
        recalculateAccountBalances()
        
        // STEP 4: Save to storage
        saveToStorage()
        
        print("✅ [BALANCE] RESET: Complete! All balances recalculated from scratch.")
    }
    
    func recalculateAccountBalances() {
        guard !accounts.isEmpty else {
            print("⚠️ [BALANCE] recalculateAccountBalances: accounts is empty, returning")
            return
        }

        print("🔄 [BALANCE] Starting recalculateAccountBalances")
        print("📊 [BALANCE] Current accounts count: \(accounts.count)")

        // Логируем текущие балансы до пересчета
        for account in accounts {
            print("💰 [BALANCE] BEFORE - Account '\(account.name)' (ID: \(account.id)): balance = \(account.balance)")
        }

        currencyConversionWarning = nil
        var balanceChanges: [String: Double] = [:]
        for account in accounts {
            balanceChanges[account.id] = 0
            if initialAccountBalances[account.id] == nil {
                // CRITICAL: Calculate initial balance by subtracting all transactions from current balance
                // This ensures we don't double-count transactions
                let transactionsSum = calculateTransactionsBalance(for: account.id)
                let initialBalance = account.balance - transactionsSum
                initialAccountBalances[account.id] = initialBalance
                print("📝 [BALANCE] Set initial balance for '\(account.name)': \(initialBalance) (current: \(account.balance), transactions: \(transactionsSum))")
            } else {
                print("📝 [BALANCE] Initial balance for '\(account.name)': \(initialAccountBalances[account.id] ?? 0)")
            }
        }

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        var hasConversionIssues = false
        
        for tx in allTransactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }
            
            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] += amountToUse
                }
            case .expense:
                if let accountId = tx.accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] -= amountToUse
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break
            case .internalTransfer:
                if let sourceId = tx.accountId,
                   let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                    let sourceAmount: Double
                    if tx.currency == sourceAccount.currency {
                        sourceAmount = tx.amount
                    } else if let converted = tx.convertedAmount {
                        sourceAmount = converted
                    } else {
                        if let converted = CurrencyConverter.convertSync(
                            amount: tx.amount,
                            from: tx.currency,
                            to: sourceAccount.currency
                        ) {
                            sourceAmount = converted
                        } else {
                            print("⚠️ Не удалось конвертировать \(tx.amount) \(tx.currency) в \(sourceAccount.currency) для счета-источника. Баланс может быть неточным.")
                            hasConversionIssues = true
                            sourceAmount = tx.amount
                        }
                    }
                    balanceChanges[sourceId, default: 0] -= sourceAmount
                }

                if let targetId = tx.targetAccountId,
                   let targetAccount = accounts.first(where: { $0.id == targetId }) {
                    let targetAmount: Double
                    if tx.currency == targetAccount.currency {
                        targetAmount = tx.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: tx.amount,
                        from: tx.currency,
                        to: targetAccount.currency
                    ) {
                        targetAmount = converted
                    } else {
                        print("⚠️ Не удалось конвертировать \(tx.amount) \(tx.currency) в \(targetAccount.currency) для счета-получателя. Баланс может быть неточным.")
                        print("⚠️ Перевод ID: \(tx.id), Описание: \(tx.description)")
                        print("⚠️ Курсы валют не загружены в кэш. Проверьте подключение к интернету и перезапустите приложение.")
                        hasConversionIssues = true
                        targetAmount = tx.amount
                    }
                    balanceChanges[targetId, default: 0] += targetAmount
                }
            }
        }

        print("📊 [BALANCE] Processing balance changes for \(accounts.count) accounts")
        for (accountId, change) in balanceChanges {
            if change != 0 {
                let accountName = accounts.first(where: { $0.id == accountId })?.name ?? "Unknown"
                print("💸 [BALANCE] Balance change for '\(accountName)': \(change)")
            }
        }

        // Создаем новый массив вместо модификации элементов на месте
        // Это необходимо для корректной работы @Published property wrapper
        var newAccounts = accounts

        for index in newAccounts.indices {
            let accountId = newAccounts[index].id
            let accountName = newAccounts[index].name
            let oldBalance = newAccounts[index].balance

            if newAccounts[index].isDeposit {
                if let depositInfo = newAccounts[index].depositInfo {
                    var totalBalance: Decimal = depositInfo.principalBalance
                    if !depositInfo.capitalizationEnabled {
                        totalBalance += depositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[index].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                    print("🏦 [BALANCE] DEPOSIT '\(accountName)': \(oldBalance) -> \(newAccounts[index].balance)")
                }
            } else {
                let initialBalance = initialAccountBalances[accountId] ?? newAccounts[index].balance
                let changes = balanceChanges[accountId] ?? 0
                newAccounts[index].balance = initialBalance + changes
                print("💳 [BALANCE] REGULAR '\(accountName)': \(oldBalance) -> \(newAccounts[index].balance) (initial: \(initialBalance), changes: \(changes))")
            }
        }

        // Переприсваиваем весь массив для триггера @Published
        print("📢 [BALANCE] Reassigning accounts array to trigger @Published")
        accounts = newAccounts

        print("✅ [BALANCE] Finished recalculateAccountBalances")
        // Логируем финальные балансы после пересчета
        for account in accounts {
            print("💰 [BALANCE] AFTER - Account '\(account.name)' (ID: \(account.id)): balance = \(account.balance)")
        }

        // Синхронизируем обновленные балансы с AccountsViewModel
        if let accountsVM = accountsViewModel {
            print("🔗 [BALANCE] Syncing balances with AccountsViewModel")
            accountsVM.syncAccountBalances(accounts)
        } else {
            print("⚠️ [BALANCE] AccountsViewModel is nil, skipping balance sync")
        }

        if hasConversionIssues {
            currencyConversionWarning = "Не удалось конвертировать валюты для некоторых переводов. Балансы могут быть неточными. Проверьте подключение к интернету."
        }
    }
    
    // MARK: - Recurring Transactions
    
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
        saveToStorage()
        generateRecurringTransactions()
        return series
    }
    
    func updateRecurringSeries(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate
            
            recurringSeries[index] = series
            
            if frequencyChanged || startDateChanged {
                let today = Calendar.current.startOfDay(for: Date())
                let dateFormatter = Self.dateFormatter
                
                let futureOccurrences = recurringOccurrences.filter { occurrence in
                    guard occurrence.seriesId == series.id,
                          let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                        return false
                    }
                    return occurrenceDate > today
                }
                
                for occurrence in futureOccurrences {
                    allTransactions.removeAll { $0.id == occurrence.transactionId }
                    recurringOccurrences.removeAll { $0.id == occurrence.id }
                }
            }
            
            saveToStorage()
            generateRecurringTransactions()
        }
    }
    
    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            recurringSeries[index].isActive = false
            saveToStorage()
        }
    }
    
    func deleteRecurringSeries(_ seriesId: String) {
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        recurringSeries.removeAll { $0.id == seriesId }
        saveToStorage()
        
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }
    }
    
    // MARK: - Subscriptions
    
    /// Get all subscriptions
    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }
    
    /// Get active subscriptions
    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }
    
    /// Create a new subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.createSubscription instead
    
    /// Update a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.updateSubscription instead
    
    /// Pause a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.pauseSubscription instead
    
    /// Resume a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.resumeSubscription instead
    
    func archiveSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            recurringSeries[index].status = .archived
            recurringSeries[index].isActive = false
            saveToStorage()
            
            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }
    
    func transactions(for subscriptionId: String) -> [Transaction] {
        allTransactions.filter { $0.recurringSeriesId == subscriptionId }
            .sorted { $0.date > $1.date }
    }
    
    func nextChargeDate(for subscriptionId: String) -> Date? {
        guard let series = recurringSeries.first(where: { $0.id == subscriptionId && $0.isSubscription }) else {
            return nil
        }
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }
    
    private static var timeFormatter: DateFormatter {
        DateFormatters.timeFormatter
    }
    
    func generateRecurringTransactions() {
        PerformanceProfiler.start("generateRecurringTransactions")
        
        // Use defer to ensure PerformanceProfiler.end is always called
        defer {
            PerformanceProfiler.end("generateRecurringTransactions")
        }
        
        let dateFormatter = Self.dateFormatter
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let horizonDate = calendar.date(byAdding: .month, value: 3, to: today) else {
            return
        }
        
        // Skip if no active recurring series
        if recurringSeries.filter({ $0.isActive }).isEmpty {
            print("⏭️ [RECURRING] No active recurring series, skipping generation")
            return
        }
        
        let existingTransactionIds = Set(allTransactions.map { $0.id })
        var existingOccurrenceKeys: Set<String> = []
        for occurrence in recurringOccurrences {
            existingOccurrenceKeys.insert("\(occurrence.seriesId):\(occurrence.occurrenceDate)")
        }
        
        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []
        var hasChanges = false
        
        for i in allTransactions.indices {
            let transaction = allTransactions[i]
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate <= today {
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
                    recurringSeriesId: nil,
                    recurringOccurrenceId: nil,
                    createdAt: transaction.createdAt
                )
                allTransactions[i] = updatedTransaction
                hasChanges = true
            }
        }
        
        for series in recurringSeries where series.isActive {
            guard let startDate = dateFormatter.date(from: series.startDate) else { continue }
            
            var currentDate: Date
            if startDate <= today {
                guard let nextDate = {
                    switch series.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: today)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: today)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: today)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: today)
                    }
                }() else {
                    continue
                }
                currentDate = nextDate
            } else {
                currentDate = startDate
            }
            
            while currentDate <= horizonDate {
                let dateString = dateFormatter.string(from: currentDate)
                let occurrenceKey = "\(series.id):\(dateString)"
                
                if !existingOccurrenceKeys.contains(occurrenceKey) {
                    let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
                    let transactionDate = dateFormatter.date(from: dateString) ?? Date()
                    let createdAt = transactionDate.timeIntervalSince1970
                    
                    let transactionId = TransactionIDGenerator.generateID(
                        date: dateString,
                        description: series.description,
                        amount: amountDouble,
                        type: .expense,
                        currency: series.currency,
                        createdAt: createdAt
                    )
                    
                    if !existingTransactionIds.contains(transactionId) {
                        let occurrenceId = UUID().uuidString
                        let transaction = Transaction(
                            id: transactionId,
                            date: dateString,
                            description: series.description,
                            amount: amountDouble,
                            currency: series.currency,
                            convertedAmount: nil,
                            type: .expense,
                            category: series.category,
                            subcategory: series.subcategory,
                            accountId: series.accountId,
                            targetAccountId: series.targetAccountId,
                            recurringSeriesId: series.id,
                            recurringOccurrenceId: occurrenceId,
                            createdAt: createdAt
                        )
                        
                        let occurrence = RecurringOccurrence(
                            id: occurrenceId,
                            seriesId: series.id,
                            occurrenceDate: dateString,
                            transactionId: transactionId
                        )
                        
                        newTransactions.append(transaction)
                        newOccurrences.append(occurrence)
                        existingOccurrenceKeys.insert(occurrenceKey)
                    }
                }
                
                guard let nextDate = {
                    switch series.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: currentDate)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: currentDate)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: currentDate)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: currentDate)
                    }
                }() else {
                    break
                }
                currentDate = nextDate
            }
        }
        
        if !newTransactions.isEmpty {
            insertTransactionsSorted(newTransactions)
            recurringOccurrences.append(contentsOf: newOccurrences)
            recalculateAccountBalances()
            saveToStorage()
            
            Task {
                for series in recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        } else if hasChanges {
            recalculateAccountBalances()
            saveToStorage()
            
            Task {
                for series in recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        }
        
        print("✅ [RECURRING] Generated \(newTransactions.count) new recurring transactions")
    }
    
    func updateRecurringTransaction(_ transactionId: String, updateAllFuture: Bool, newAmount: Decimal? = nil, newCategory: String? = nil, newSubcategory: String? = nil) {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }),
              let seriesId = transaction.recurringSeriesId,
              let seriesIndex = recurringSeries.firstIndex(where: { $0.id == seriesId }) else {
            return
        }
        
        if updateAllFuture {
            if let newAmount = newAmount {
                recurringSeries[seriesIndex].amount = newAmount
            }
            if let newCategory = newCategory {
                recurringSeries[seriesIndex].category = newCategory
            }
            if let newSubcategory = newSubcategory {
                recurringSeries[seriesIndex].subcategory = newSubcategory
            }
            
            let dateFormatter = Self.dateFormatter
            guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }

            let futureOccurrences = recurringOccurrences.filter { occurrence in
                guard occurrence.seriesId == seriesId,
                      let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                    return false
                }
                return occurrenceDate >= transactionDate
            }
            
            for occurrence in futureOccurrences {
                allTransactions.removeAll { $0.id == occurrence.transactionId }
                recurringOccurrences.removeAll { $0.id == occurrence.id }
            }
            
            generateRecurringTransactions()
        } else {
            if let index = allTransactions.firstIndex(where: { $0.id == transactionId }) {
                var updatedTransaction = allTransactions[index]
                if let newAmount = newAmount {
                    let amountDouble = NSDecimalNumber(decimal: newAmount).doubleValue
                    updatedTransaction = Transaction(
                        id: updatedTransaction.id,
                        date: updatedTransaction.date,
                        description: updatedTransaction.description,
                        amount: amountDouble,
                        currency: updatedTransaction.currency,
                        convertedAmount: updatedTransaction.convertedAmount,
                        type: updatedTransaction.type,
                        category: newCategory ?? updatedTransaction.category,
                        subcategory: newSubcategory ?? updatedTransaction.subcategory,
                        accountId: updatedTransaction.accountId,
                        targetAccountId: updatedTransaction.targetAccountId,
                        recurringSeriesId: updatedTransaction.recurringSeriesId,
                        recurringOccurrenceId: updatedTransaction.recurringOccurrenceId,
                        createdAt: updatedTransaction.createdAt
                    )
                    allTransactions[index] = updatedTransaction
                }
            }
        }
        
        saveToStorage()
    }
    
    // MARK: - Subcategories
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.addSubcategory instead
    
    func updateSubcategory(_ subcategory: Subcategory) {
        if let index = subcategories.firstIndex(where: { $0.id == subcategory.id }) {
            subcategories[index] = subcategory
            saveToStorage()
        }
    }
    
    func deleteSubcategory(_ subcategoryId: String) {
        categorySubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        transactionSubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        subcategories.removeAll { $0.id == subcategoryId }
        saveToStorage()
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.linkSubcategoryToCategory instead
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.unlinkSubcategoryFromCategory instead
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.getSubcategoriesForCategory instead
    
    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = transactionSubcategoryLinks
            .filter { $0.transactionId == transactionId }
            .map { $0.subcategoryId }
        
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }
    
    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }
        
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            transactionSubcategoryLinks.append(link)
        }
        
        saveToStorage()
    }
    
    func searchSubcategories(query: String) -> [Subcategory] {
        let queryLower = query.lowercased()
        return subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }

    // MARK: - Transaction Indexes

    /// Rebuild transaction indexes for fast filtering
    func rebuildIndexes() {
        print("📇 [INDEX] Rebuilding transaction indexes")
        indexManager.buildIndexes(transactions: allTransactions)
    }

    // MARK: - Currency Conversion Cache

    /// Precompute currency conversions for all transactions in background
    /// This dramatically improves UI performance by avoiding sync conversions
    func precomputeCurrencyConversions() {
        guard conversionCacheInvalidated else {
            print("💱 [CONVERSION] Cache is valid, skipping precomputation")
            return
        }

        print("💱 [CONVERSION] Starting precomputation for \(allTransactions.count) transactions")
        PerformanceProfiler.start("precomputeCurrencyConversions")

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let baseCurrency = await MainActor.run { self.appSettings.baseCurrency }
            let transactions = await MainActor.run { self.allTransactions }

            var cache: [String: Double] = [:]
            var conversionCount = 0

            for tx in transactions {
                let cacheKey = "\(tx.id)_\(baseCurrency)"

                if tx.currency == baseCurrency {
                    cache[cacheKey] = tx.amount
                } else {
                    // Call convertSync on MainActor since it's @MainActor isolated
                    let converted = await MainActor.run {
                        CurrencyConverter.convertSync(
                            amount: tx.amount,
                            from: tx.currency,
                            to: baseCurrency
                        )
                    }
                    
                    if let converted = converted {
                        cache[cacheKey] = converted
                        conversionCount += 1
                    } else if let convertedAmount = tx.convertedAmount {
                        // Fallback to stored converted amount
                        cache[cacheKey] = convertedAmount
                    }
                }
            }

            // Capture values before passing to MainActor
            let finalConversionCount = conversionCount
            let finalCacheCount = cache.count
            let cacheCopy = cache // Create a copy to avoid concurrent access issues

            await MainActor.run {
                self.convertedAmountsCache = cacheCopy
                self.conversionCacheInvalidated = false
                print("✅ [CONVERSION] Precomputed \(finalConversionCount) conversions, cached \(finalCacheCount) amounts")
                PerformanceProfiler.end("precomputeCurrencyConversions")
            }
        }
    }

    /// Get converted amount from cache
    /// - Parameters:
    ///   - transactionId: Transaction ID
    ///   - baseCurrency: Target currency
    /// - Returns: Converted amount or nil if not cached
    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        let cacheKey = "\(transactionId)_\(baseCurrency)"
        return convertedAmountsCache[cacheKey]
    }

    /// Get converted amount for a transaction, falling back to sync conversion if not cached
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - baseCurrency: Target currency
    /// - Returns: Converted amount
    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        // Try cache first
        if let cached = getConvertedAmount(transactionId: transaction.id, to: baseCurrency) {
            return cached
        }

        // Fallback to sync conversion (should be rare after precomputation)
        if transaction.currency == baseCurrency {
            return transaction.amount
        } else if let converted = CurrencyConverter.convertSync(
            amount: transaction.amount,
            from: transaction.currency,
            to: baseCurrency
        ) {
            return converted
        } else {
            return transaction.convertedAmount ?? transaction.amount
        }
    }
}

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
