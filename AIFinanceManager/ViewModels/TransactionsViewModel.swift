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
    
    /// Transactions optimized for UI display (recent 12 months by default)
    /// Use this for lists and UI rendering for better performance
    @Published var displayTransactions: [Transaction] = []
    
    /// Controls how many months to load for initial display (default: 12 months)
    var displayMonthsRange: Int = 12
    
    /// Indicates if older transactions are available to load
    @Published var hasOlderTransactions: Bool = false
    
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
    // КРИТИЧЕСКИ ВАЖНО: Сохраняем, какие аккаунты имеют initialBalance, рассчитанный автоматически
    // Для этих аккаунтов транзакции НЕ должны обрабатываться повторно
    private var accountsWithCalculatedInitialBalance: Set<String> = []
    private var cachedSummary: Summary?
    private var summaryCacheInvalidated = true
    private var cachedCategoryExpenses: [String: CategoryExpense]?
    private var categoryExpensesCacheInvalidated = true

    // Currency conversion cache: "txId_baseCurrency" -> converted amount
    private var convertedAmountsCache: [String: Double] = [:]
    private var conversionCacheInvalidated = true

    // Transaction indexes for fast filtering
    private let indexManager = TransactionIndexManager()
    
    // MARK: - Batch Mode for Performance
    
    /// Batch mode delays expensive operations (balance recalculation, saving) until endBatch()
    /// Use this when performing multiple operations at once (e.g., CSV import, bulk delete)
    private var isBatchMode = false
    private var pendingBalanceRecalculation = false
    private var pendingSave = false

    func invalidateCaches() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
        conversionCacheInvalidated = true
        indexManager.invalidate()
    }

    // MARK: - Dependencies

    /// Account balance service for synchronizing balances
    /// Strong reference prevents silent failures when updating balances
    private let accountBalanceService: AccountBalanceServiceProtocol

    // MARK: - Repository

    let repository: DataRepositoryProtocol

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol = UserDefaultsRepository(),
        accountBalanceService: AccountBalanceServiceProtocol
    ) {
        self.repository = repository
        self.accountBalanceService = accountBalanceService
        print("🏗️ [INIT] Initializing TransactionsViewModel (deferred loading)")
        print("🔗 [INIT] AccountBalanceService injected: \(type(of: accountBalanceService))")
        // Don't load data synchronously in init - use loadDataAsync() instead
        
        // Setup observers for recurring series changes
        setupRecurringSeriesObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Setup observer for recurring series changes
    private func setupRecurringSeriesObserver() {
        // Listen for NEW recurring series created
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesCreated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let seriesId = notification.userInfo?["seriesId"] as? String else {
                return
            }
            
            print("📢 [OBSERVER] Received recurringSeriesCreated for series: \(seriesId)")
            print("🔄 [OBSERVER] Generating transactions for new series")
            self.generateRecurringTransactions()
            
            // Recalculate balances and save
            self.invalidateCaches()
            self.rebuildIndexes()
            self.scheduleBalanceRecalculation()
            self.scheduleSave()
        }
        
        // Listen for UPDATED recurring series (regenerate only affected series)
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let seriesId = notification.userInfo?["seriesId"] as? String else {
                return
            }
            
            print("📢 [OBSERVER] Received recurringSeriesChanged for series: \(seriesId)")
            self.regenerateRecurringTransactions(for: seriesId)
        }
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

            // Get ALL transactions in the time range, not just the first one
            let transactionsInRange = seriesTransactions.filter { transaction in
                guard let date = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return date >= range.start && date < range.end
            }

            recurringTransactions.append(contentsOf: transactionsInRange)
        }
        
        return recurringTransactions + regularTransactions
    }
    
    // MARK: - History View Filtering and Grouping
    
    /// Фильтрует транзакции для HistoryView с учетом всех фильтров (время, категории, счет, поиск)
    /// Для повторяющихся транзакций показывает только ближайшую
    func filterTransactionsForHistory(
        timeFilterManager: TimeFilterManager,
        accountId: String?,
        searchText: String
    ) -> [Transaction] {
        var transactions = transactionsFilteredByTimeAndCategory(timeFilterManager)

        // For history view: show only the nearest transaction for each recurring series
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]

        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }

        // Get only the nearest (min date) transaction for each recurring series
        let dateFormatter = Self.dateFormatter
        var nearestRecurringTransactions: [Transaction] = []

        for (_, seriesTransactions) in recurringTransactionsBySeries {
            let transactionsWithDates = seriesTransactions.compactMap { transaction -> (Transaction, Date)? in
                guard let date = dateFormatter.date(from: transaction.date) else {
                    return nil
                }
                return (transaction, date)
            }

            if let nearest = transactionsWithDates.min(by: { $0.1 < $1.1 })?.0 {
                nearestRecurringTransactions.append(nearest)
            }
        }

        transactions = regularTransactions + nearestRecurringTransactions
        
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
            scheduleBalanceRecalculation()
            scheduleSave()
        }
    }
    
    /// Добавляет транзакции для импорта (используйте beginBatch/endBatch для оптимизации)
    /// Example:
    /// ```
    /// viewModel.beginBatch()
    /// viewModel.addTransactionsForImport(transactions)
    /// viewModel.endBatch() // Balance calculation happens once here
    /// ```
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
            scheduleBalanceRecalculation()
            print("💾 [TRANSACTION] Saving to storage")
            scheduleSave()
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
        print("🗑️ [TRANSACTION] ========== DELETING TRANSACTION ==========")
        print("🗑️ [TRANSACTION] Description: \(transaction.description)")
        print("🗑️ [TRANSACTION] Amount: \(transaction.amount) \(transaction.currency)")
        print("🗑️ [TRANSACTION] Type: \(transaction.type)")
        print("🗑️ [TRANSACTION] Account ID: \(transaction.accountId ?? "nil")")
        
        // Логируем балансы ДО удаления
        print("💰 [TRANSACTION] BALANCES BEFORE DELETE:")
        for account in accounts {
            print("   💳 '\(account.name)': \(account.balance)")
        }
        print("📊 [TRANSACTION] Initial balances: \(initialAccountBalances)")

        // removeAll уже создает новый массив, что правильно триггерит @Published
        allTransactions.removeAll { $0.id == transaction.id }
        print("📢 [TRANSACTION] allTransactions updated after delete, count: \(allTransactions.count)")

        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        // КРИТИЧЕСКИ ВАЖНО: Удаляем затронутые аккаунты из Set,
        // чтобы их балансы были пересчитаны с новым списком транзакций
        if let accountId = transaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
            print("🔄 [TRANSACTION] Removed '\(accountId)' from accountsWithCalculatedInitialBalance - balance will be recalculated")
        }
        if let targetAccountId = transaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
            print("🔄 [TRANSACTION] Removed '\(targetAccountId)' from accountsWithCalculatedInitialBalance - balance will be recalculated")
        }

        print("🔄 [TRANSACTION] Recalculating balances after delete")
        invalidateCaches()
        scheduleBalanceRecalculation()
        
        // Note: Balance logging happens after recalculation completes
        if !isBatchMode {
            print("💰 [TRANSACTION] BALANCES AFTER RECALCULATE:")
            for account in accounts {
                print("   💳 '\(account.name)': \(account.balance)")
            }
        }
        
        scheduleSave()
        
        print("✅ [TRANSACTION] ========== DELETE COMPLETED ==========")
    }

    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }

        print("✏️ [TRANSACTION] Updating transaction: \(transaction.description), amount: \(transaction.amount)")

        // КРИТИЧЕСКИ ВАЖНО: Удаляем затронутые аккаунты из Set,
        // чтобы их балансы были пересчитаны с новым списком транзакций
        let oldTransaction = allTransactions[index]
        if let accountId = oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
            print("🔄 [TRANSACTION] Removed '\(accountId)' from accountsWithCalculatedInitialBalance - balance will be recalculated")
        }
        if let targetAccountId = oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
            print("🔄 [TRANSACTION] Removed '\(targetAccountId)' from accountsWithCalculatedInitialBalance - balance will be recalculated")
        }
        // Также удаляем новые аккаунты, если они изменились
        if let accountId = transaction.accountId, accountId != oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = transaction.targetAccountId, targetAccountId != oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }

        // Создаем новый массив вместо модификации элемента на месте
        var newTransactions = allTransactions
        newTransactions[index] = transaction

        // Переприсваиваем весь массив для триггера @Published
        print("📢 [TRANSACTION] Reassigning allTransactions array to trigger @Published")
        allTransactions = newTransactions

        invalidateCaches()
        scheduleBalanceRecalculation()
        scheduleSave()
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
        
        // CRITICAL: Синхронизируем обновленные балансы с AccountBalanceService
        // Без этого UI не обновится, т.к. карточки счетов используют accounts
        print("🔗 [TRANSFER] Syncing balances with AccountBalanceService")
        accountBalanceService.syncAccountBalances(accounts)
        
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
            print("💾 [STORAGE] ========== STARTING ASYNC SAVE ==========")

            let transactions = await MainActor.run { self.allTransactions }
            let rules = await MainActor.run { self.categoryRules }
            let accs = await MainActor.run { self.accounts }
            let categories = await MainActor.run { self.customCategories }
            let series = await MainActor.run { self.recurringSeries }
            let occurrences = await MainActor.run { self.recurringOccurrences }

            print("💾 [STORAGE] Captured \(accs.count) accounts from TransactionsViewModel:")
            for account in accs {
                print("   💰 '\(account.name)': balance = \(account.balance)")
            }
            print("💾 [STORAGE] About to save to repository...")

            // НЕ сохраняем подкатегории и связи здесь - они управляются CategoriesViewModel
            // let subcats = await MainActor.run { self.subcategories }
            // let catLinks = await MainActor.run { self.categorySubcategoryLinks }
            // let txLinks = await MainActor.run { self.transactionSubcategoryLinks }

            await MainActor.run {
                self.repository.saveTransactions(transactions)
                self.repository.saveCategoryRules(rules)
                print("💾 [STORAGE] Calling repository.saveAccounts() with:")
                for account in accs {
                    print("   💰 '\(account.name)': balance = \(account.balance)")
                }
                self.repository.saveAccounts(accs)
                self.repository.saveCategories(categories)
                self.repository.saveRecurringSeries(series)
                self.repository.saveRecurringOccurrences(occurrences)
                // Подкатегории и связи сохраняются через CategoriesViewModel
                // self.repository.saveSubcategories(subcats)
                // self.repository.saveCategorySubcategoryLinks(catLinks)
                // self.repository.saveTransactionSubcategoryLinks(txLinks)
            }

            print("✅ [STORAGE] ========== ASYNC SAVE COMPLETED ==========")
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
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveTransactionsSync(transactions)
                print("✅ [STORAGE] Transactions saved synchronously to Core Data")
            } catch {
                print("❌ [STORAGE] Failed to save transactions to Core Data: \(error)")
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            repository.saveTransactions(transactions)
        }
    }

    private func saveCategoryRulesSync(_ rules: [CategoryRule]) {
        repository.saveCategoryRules(rules)
    }

    private func saveAccountsSync(_ accounts: [Account]) {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveAccountsSync(accounts)
                print("✅ [STORAGE] Accounts saved synchronously to Core Data")
            } catch {
                print("❌ [STORAGE] Failed to save accounts to Core Data: \(error)")
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            repository.saveAccounts(accounts)
        }
    }

    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(categories)
                print("✅ [STORAGE] Categories saved synchronously to Core Data")
            } catch {
                print("❌ [STORAGE] Failed to save categories to Core Data: \(error)")
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            repository.saveCategories(categories)
        }
    }

    private func saveRecurringSeriesSync(_ series: [RecurringSeries]) {
        repository.saveRecurringSeries(series)
    }

    private func saveRecurringOccurrencesSync(_ occurrences: [RecurringOccurrence]) {
        repository.saveRecurringOccurrences(occurrences)
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
        
        // OPTIMIZATION: Load recent transactions first for fast UI display
        let now = Date()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .month, value: -displayMonthsRange, to: now) else {
            // Fallback to loading all transactions
            allTransactions = repository.loadTransactions(dateRange: nil)
            displayTransactions = allTransactions
            hasOlderTransactions = false
            print("⚠️ [STORAGE] Failed to calculate date range, loaded all transactions")
            loadOtherData()
            return
        }
        
        let recentDateRange = DateInterval(start: startDate, end: now)
        
        // Load recent transactions for UI (fast)
        displayTransactions = repository.loadTransactions(dateRange: recentDateRange)
        print("✅ [STORAGE] Loaded \(displayTransactions.count) recent transactions (last \(displayMonthsRange) months) for display")
        
        // Load ALL transactions asynchronously for calculations
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            print("📂 [STORAGE_BG] Loading ALL transactions in background for calculations...")
            let allTxns = self.repository.loadTransactions(dateRange: nil)
            
            await MainActor.run {
                self.allTransactions = allTxns
                self.hasOlderTransactions = allTxns.count > self.displayTransactions.count
                print("✅ [STORAGE_BG] Loaded \(allTxns.count) total transactions")
                
                if self.hasOlderTransactions {
                    print("ℹ️ [STORAGE_BG] \(allTxns.count - self.displayTransactions.count) older transactions available")
                }
                
                // Recalculate caches with full data
                self.invalidateCaches()
                self.rebuildIndexes()
            }
        }
        
        loadOtherData()
    }
    
    private func loadOtherData() {
        categoryRules = repository.loadCategoryRules()
        
        // Load accounts from AccountBalanceService (single source of truth)
        accounts = accountBalanceService.accounts
        print("📊 [STORAGE] Loaded \(accounts.count) accounts from AccountBalanceService")
        
        // Note: Initial balances will be calculated after ALL transactions are loaded
        // This happens asynchronously in the background task above
        
        customCategories = repository.loadCategories()
        recurringSeries = repository.loadRecurringSeries()
        recurringOccurrences = repository.loadRecurringOccurrences()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        print("✅ [STORAGE] Core data loaded successfully")
        
        // Calculate initial balances with displayTransactions for now
        // Will be recalculated when all transactions load in background
        for account in accounts {
            print("   💰 '\(account.name)': current balance = \(account.balance)")
            if initialAccountBalances[account.id] == nil {
                // Calculate the sum of display transactions for this account (temporary)
                let transactionsSum = displayTransactions
                    .filter { $0.accountId == account.id || $0.targetAccountId == account.id }
                    .reduce(0.0) { sum, tx in
                        if tx.accountId == account.id {
                            return sum + (tx.type == .income ? tx.amount : -tx.amount)
                        } else if tx.targetAccountId == account.id {
                            return sum + tx.amount // Transfer in
                        }
                        return sum
                    }
                let initialBalance = account.balance - transactionsSum
                initialAccountBalances[account.id] = initialBalance
                print("   📝 '\(account.name)': initial balance (temporary, will recalc) = \(initialBalance)")
            }
        }

        // NOTE: Do NOT call recalculateAccountBalances() here!
        // Balances are already calculated and saved in Core Data.
        // They will be recalculated when all transactions finish loading in background

        // Build indexes for fast filtering (with displayTransactions for now)
        rebuildIndexes()

        // Precompute currency conversions in background for better UI performance
        precomputeCurrencyConversions()
    }
    
    /// Load older transactions beyond the initial display range
    /// Call this when user scrolls to the bottom or requests to view older data
    func loadOlderTransactions() {
        guard hasOlderTransactions else {
            print("ℹ️ [LOAD_OLDER] No older transactions to load")
            return
        }
        
        print("📂 [LOAD_OLDER] Loading older transactions...")
        
        // displayTransactions should now include all transactions
        displayTransactions = allTransactions
        hasOlderTransactions = false
        
        print("✅ [LOAD_OLDER] Now displaying all \(displayTransactions.count) transactions")
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
        
        // Рассчитываем initialBalance для НОВЫХ аккаунтов
        for account in accounts {
            balanceChanges[account.id] = 0
            if initialAccountBalances[account.id] == nil {
                // Рассчитываем initialBalance = current - transactionsSum
                // Это дает нам "начальный капитал", который привел к текущему балансу
                let transactionsSum = calculateTransactionsBalance(for: account.id)
                let initialBalance = account.balance - transactionsSum
                initialAccountBalances[account.id] = initialBalance
                print("📝 [BALANCE] FRESHLY CALCULATED initial balance for '\(account.name)': \(initialBalance) (current: \(account.balance), transactions: \(transactionsSum))")
                
                // КРИТИЧЕСКИ ВАЖНО: Сохраняем в instance property
                // Транзакции УЖЕ УЧТЕНЫ в current balance, поэтому НЕ должны обрабатываться снова
                accountsWithCalculatedInitialBalance.insert(account.id)
            } else {
                // initialBalance УЖЕ СУЩЕСТВУЕТ из предыдущих вызовов
                if accountsWithCalculatedInitialBalance.contains(account.id) {
                    print("📝 [BALANCE] EXISTING CALCULATED initial balance for '\(account.name)': \(initialAccountBalances[account.id] ?? 0) - will NOT process transactions (already included)")
                } else {
                    print("📝 [BALANCE] EXISTING MANUAL initial balance for '\(account.name)': \(initialAccountBalances[account.id] ?? 0) - will process transactions normally")
                }
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
                    // Пропускаем аккаунты с РАССЧИТАННЫМ initialBalance
                    guard !accountsWithCalculatedInitialBalance.contains(accountId) else { continue }
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] += amountToUse
                }
            case .expense:
                if let accountId = tx.accountId {
                    // Пропускаем аккаунты с РАССЧИТАННЫМ initialBalance
                    guard !accountsWithCalculatedInitialBalance.contains(accountId) else { continue }
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] -= amountToUse
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break
            case .internalTransfer:
                if let sourceId = tx.accountId,
                   let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                    // Пропускаем аккаунты с РАССЧИТАННЫМ initialBalance
                    guard !accountsWithCalculatedInitialBalance.contains(sourceId) else { 
                        // Проверяем также target account перед continue
                        if let targetId = tx.targetAccountId, !accountsWithCalculatedInitialBalance.contains(targetId) {
                            // Source пропускаем, но обрабатываем target ниже
                        } else {
                            continue
                        }
                        // Если дошли сюда, значит target нужно обработать, пропускаем только source
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
                                hasConversionIssues = true
                                targetAmount = tx.amount
                            }
                            balanceChanges[targetId, default: 0] += targetAmount
                        }
                        continue
                    }
                    
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
                    // Пропускаем аккаунты с РАССЧИТАННЫМ initialBalance
                    guard !accountsWithCalculatedInitialBalance.contains(targetId) else { continue }
                    
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

        // Синхронизируем обновленные балансы с AccountBalanceService
        print("🔗 [BALANCE] Syncing balances with AccountBalanceService")
        print("📊 [BALANCE] Accounts to sync:")
        for account in accounts {
            print("   💳 '\(account.name)': \(account.balance)")
        }
        
        accountBalanceService.syncAccountBalances(accounts)
        
        // ✅ Сохраняем обновленные балансы в Core Data
        print("💾 [BALANCE] Saving updated balances to Core Data")
        accountBalanceService.saveAllAccountsSync()
        
        print("✅ [BALANCE] Balance sync and save completed")

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
        print("🗑️ [RECURRING] Deleting recurring series: \(seriesId)")
        
        // CRITICAL: Delete all transactions associated with this series
        let transactionsToDelete = allTransactions.filter { $0.recurringSeriesId == seriesId }
        print("🗑️ [RECURRING] Found \(transactionsToDelete.count) transactions to delete")
        
        // Remove transactions
        allTransactions.removeAll { $0.recurringSeriesId == seriesId }
        
        // Remove occurrences
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        
        // Remove series
        recurringSeries.removeAll { $0.id == seriesId }
        
        // CRITICAL: Recalculate balances after deleting transactions
        print("🔄 [RECURRING] Recalculating balances after series deletion")
        invalidateCaches()
        rebuildIndexes()
        scheduleBalanceRecalculation()
        
        scheduleSave()
        
        // Cancel notifications
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }
        
        print("✅ [RECURRING] Series and associated transactions deleted")
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
    
    /// Regenerate transactions for a specific recurring series after it was updated
    /// Deletes future transactions and generates new ones based on updated series
    /// - Parameter seriesId: ID of the recurring series that was updated
    private func regenerateRecurringTransactions(for seriesId: String) {
        print("🔄 [RECURRING_REGEN] Starting regeneration for series: \(seriesId)")
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Step 1: Delete all FUTURE transactions for this series
        let futureTransactionsCount = allTransactions.filter { transaction in
            guard transaction.recurringSeriesId == seriesId else { return false }
            guard let date = DateFormatters.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return date > today
        }.count
        
        print("🗑️ [RECURRING_REGEN] Deleting \(futureTransactionsCount) future transactions")
        allTransactions.removeAll { transaction in
            guard transaction.recurringSeriesId == seriesId else { return false }
            guard let date = DateFormatters.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return date > today
        }
        
        // Step 2: Delete future occurrences
        recurringOccurrences.removeAll { occurrence in
            guard occurrence.seriesId == seriesId else { return false }
            guard let date = DateFormatters.dateFormatter.date(from: occurrence.occurrenceDate) else {
                return false
            }
            return date > today
        }
        
        // Step 3: Regenerate transactions for this series
        print("♻️ [RECURRING_REGEN] Regenerating transactions")
        generateRecurringTransactions()
        
        // Step 4: Recalculate balances
        print("💰 [RECURRING_REGEN] Recalculating account balances")
        invalidateCaches()
        rebuildIndexes()
        scheduleBalanceRecalculation()
        
        // Step 5: Save
        scheduleSave()
        
        print("✅ [RECURRING_REGEN] Regeneration completed for series: \(seriesId)")
    }
    
    func generateRecurringTransactions() {
        PerformanceProfiler.start("generateRecurringTransactions")

        // Use defer to ensure PerformanceProfiler.end is always called
        defer {
            PerformanceProfiler.end("generateRecurringTransactions")
        }

        // CRITICAL: Reload recurringSeries and recurringOccurrences from repository to get latest data
        // This ensures we have the latest subscriptions created by SubscriptionsViewModel
        // and prevents deleted occurrences from being restored
        recurringSeries = repository.loadRecurringSeries()
        recurringOccurrences = repository.loadRecurringOccurrences()
        print("🔄 [RECURRING] Reloaded \(recurringSeries.count) recurring series and \(recurringOccurrences.count) occurrences from storage")

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
        
        for series in recurringSeries where series.isActive {
            guard let startDate = dateFormatter.date(from: series.startDate) else { continue }

            // Always start from the startDate to generate past transactions
            var currentDate = startDate
            var iterationCount = 0
            let maxIterations = 10000 // Safety limit to prevent infinite loops

            while currentDate <= horizonDate && iterationCount < maxIterations {
                iterationCount += 1
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

                // Additional safety check: ensure we're actually moving forward in time
                if nextDate <= currentDate {
                    print("⚠️ [RECURRING] ERROR: nextDate (\(nextDate)) is not greater than currentDate (\(currentDate)) for series \(series.id). Breaking to prevent infinite loop.")
                    break
                }

                currentDate = nextDate
            }

            if iterationCount >= maxIterations {
                print("⚠️ [RECURRING] WARNING: Reached maximum iteration limit (\(maxIterations)) for series \(series.id). This may indicate a problem with date calculation.")
            }
        }
        
        // First, insert new transactions if any
        if !newTransactions.isEmpty {
            insertTransactionsSorted(newTransactions)
            recurringOccurrences.append(contentsOf: newOccurrences)
            print("✅ [RECURRING] Generated \(newTransactions.count) new recurring transactions")
        }

        // Now convert past recurring transactions to regular transactions
        // This must happen AFTER insertion to catch newly created transactions with past dates
        var updatedAllTransactions = allTransactions
        var convertedCount = 0
        for i in updatedAllTransactions.indices {
            let transaction = updatedAllTransactions[i]
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
                updatedAllTransactions[i] = updatedTransaction
                convertedCount += 1
            }
        }

        // Reassign to trigger @Published if conversions happened
        let needsSave = !newTransactions.isEmpty || convertedCount > 0
        if convertedCount > 0 {
            print("🔄 [RECURRING] Converted \(convertedCount) past recurring transactions to regular transactions")
            allTransactions = updatedAllTransactions
        }

        // Recalculate and save if there were any changes
        if needsSave {
            scheduleBalanceRecalculation()
            scheduleSave()

            Task {
                for series in recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        }
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
    
    // MARK: - Batch Mode Operations
    
    /// Begin batch mode - delays expensive operations until endBatch()
    /// Use this when performing multiple operations (CSV import, bulk operations)
    /// Example:
    /// ```
    /// viewModel.beginBatch()
    /// for transaction in transactions {
    ///     viewModel.addTransaction(transaction)
    /// }
    /// viewModel.endBatch() // Balance recalculation happens once here
    /// ```
    func beginBatch() {
        print("📦 [BATCH] Starting batch mode")
        isBatchMode = true
        pendingBalanceRecalculation = false
        pendingSave = false
    }
    
    /// End batch mode and perform all pending operations
    /// This will recalculate balances and save if needed
    func endBatch() {
        print("📦 [BATCH] Ending batch mode")
        isBatchMode = false
        
        var operationsPerformed: [String] = []
        
        if pendingBalanceRecalculation {
            print("💰 [BATCH] Performing pending balance recalculation")
            recalculateAccountBalances()
            operationsPerformed.append("balance recalc")
            pendingBalanceRecalculation = false
        }
        
        if pendingSave {
            print("💾 [BATCH] Performing pending save")
            saveToStorage()
            operationsPerformed.append("save")
            pendingSave = false
        }
        
        if operationsPerformed.isEmpty {
            print("✅ [BATCH] Complete - no operations were needed")
        } else {
            print("✅ [BATCH] Complete - performed: \(operationsPerformed.joined(separator: ", "))")
        }
    }
    
    /// Helper method to schedule balance recalculation
    /// In batch mode, this is delayed until endBatch()
    /// In normal mode, this is executed immediately
    private func scheduleBalanceRecalculation() {
        if isBatchMode {
            pendingBalanceRecalculation = true
            print("📦 [BATCH] Balance recalculation scheduled (deferred)")
        } else {
            recalculateAccountBalances()
        }
    }
    
    /// Helper method to schedule save
    /// In batch mode, this is delayed until endBatch()
    /// In normal mode, this is executed immediately
    private func scheduleSave() {
        if isBatchMode {
            pendingSave = true
            print("📦 [BATCH] Save scheduled (deferred)")
        } else {
            saveToStorage()
        }
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
