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
    
    /// Controls how many months to load for initial display
    /// PERFORMANCE: Уменьшено с 12 до 6 месяцев для ускорения первоначальной загрузки
    /// При 19K+ транзакций это значительно уменьшает объем обрабатываемых данных
    var displayMonthsRange: Int = 6
    
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

    // MARK: - Balance Calculation Service

    /// Service for unified balance calculation logic
    /// Manages imported account tracking and provides consistent balance calculation
    private let balanceCalculationService: BalanceCalculationServiceProtocol

    /// Координатор для сериализации операций с балансами
    /// Предотвращает race conditions при одновременном обновлении балансов
    private let balanceUpdateCoordinator = BalanceUpdateCoordinatorWrapper()

    // КРИТИЧЕСКИ ВАЖНО: Сохраняем, какие аккаунты имеют initialBalance, рассчитанный автоматически
    // Для этих аккаунтов транзакции НЕ должны обрабатываться повторно
    // NOTE: Теперь управляется через balanceCalculationService.isImported()
    // Этот Set оставлен для обратной совместимости и будет удален в следующей версии
    private var accountsWithCalculatedInitialBalance: Set<String> = []

    // MARK: - Category Aggregation

    /// Кеш агрегатов категорий для быстрого O(1) доступа
    private let aggregateCache = CategoryAggregateCache()

    // MARK: - Extracted Services (P3 decomposition)

    /// Centralized cache manager for summaries, balances, account lookups, and indexes
    let cacheManager = TransactionCacheManager()

    /// Currency conversion cache service
    let currencyService = TransactionCurrencyService()

    // MARK: - Decomposed Services (Phase 2)

    /// Filter service for transaction filtering operations
    private lazy var filterService: TransactionFilterService = {
        TransactionFilterService(dateFormatter: Self.dateFormatter)
    }()

    /// Grouping service for transaction grouping and sorting
    private lazy var groupingService: TransactionGroupingService = {
        TransactionGroupingService(
            dateFormatter: Self.dateFormatter,
            displayDateFormatter: DateFormatters.displayDateFormatter,
            displayDateWithYearFormatter: DateFormatters.displayDateWithYearFormatter
        )
    }()

    /// Balance calculator for account balance calculations
    private lazy var balanceCalculator: BalanceCalculator = {
        BalanceCalculator(dateFormatter: Self.dateFormatter)
    }()

    /// Recurring transaction generator for creating recurring transactions
    private lazy var recurringGenerator: RecurringTransactionGenerator = {
        RecurringTransactionGenerator(dateFormatter: Self.dateFormatter)
    }()

    // MARK: - Batch Mode for Performance

    /// Batch mode delays expensive operations (balance recalculation, saving) until endBatch()
    /// Use this when performing multiple operations at once (e.g., CSV import, bulk delete)
    private var isBatchMode = false
    private var pendingBalanceRecalculation = false
    private var pendingSave = false

    // MARK: - Notification Processing Guard

    /// Prevents concurrent processing of recurring series notifications
    /// This avoids race conditions when multiple notifications arrive simultaneously
    private var isProcessingRecurringNotification = false

    // MARK: - Save Debouncing

    /// Debouncer for saveToStorage to prevent excessive saves
    /// Delays save operation by 500ms after last change
    private var saveDebouncer: AnyCancellable?
    private var saveCancellables = Set<AnyCancellable>()

    func invalidateCaches() {
        cacheManager.invalidateAll()
        currencyService.invalidate()
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
        accountBalanceService: AccountBalanceServiceProtocol,
        balanceCalculationService: BalanceCalculationServiceProtocol = BalanceCalculationService()
    ) {
        self.repository = repository
        self.accountBalanceService = accountBalanceService
        self.balanceCalculationService = balanceCalculationService

        // PERFORMANCE: Set cache manager for optimized date parsing in balance calculations
        if let concreteService = balanceCalculationService as? BalanceCalculationService {
            concreteService.setCacheManager(cacheManager)
        }

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
                  let _ = notification.userInfo?["seriesId"] as? String else {
                return
            }

            // Guard against concurrent processing to prevent race conditions
            guard !self.isProcessingRecurringNotification else {
                return
            }
            self.isProcessingRecurringNotification = true
            defer { self.isProcessingRecurringNotification = false }

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

            // Guard against concurrent processing to prevent race conditions
            guard !self.isProcessingRecurringNotification else {
                return
            }
            self.isProcessingRecurringNotification = true
            defer { self.isProcessingRecurringNotification = false }

            self.regenerateRecurringTransactions(for: seriesId)
        }
    }
    
    private var isDataLoaded = false
    
    /// Load all data asynchronously for better app startup performance
    func loadDataAsync() async {
        // Prevent double loading
        guard !isDataLoaded else {
            return
        }

        isDataLoaded = true
        PerformanceProfiler.start("TransactionsViewModel.loadDataAsync")

        await MainActor.run {
            isLoading = true
        }

        // STEP 1: Load data (WAIT for completion to ensure allTransactions is populated)
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.loadFromStorage()
        }.value

        // STEP 2: Generate recurring transactions (WAIT for completion)
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                self.generateRecurringTransactions()
            }
        }.value

        // STEP 3: Initialize aggregates AFTER data is fully loaded
        // Now allTransactions is guaranteed to be populated
        await initializeCategoryAggregates()

        await MainActor.run {
            isLoading = false
        }

        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
    }

    /// Инициализировать кеш агрегатов категорий (миграция или загрузка)
    private func initializeCategoryAggregates() async {
        let currentVersion = UserDefaults.standard.integer(forKey: "aggregateCacheVersion")

        if currentVersion < 1 {
            // Первый запуск - выполнить миграцию
            await migrateToAggregateCache()
        } else {
            // Обычная загрузка из CoreData
            guard let coreDataRepo = repository as? CoreDataRepository else { return }
            await aggregateCache.loadFromCoreData(repository: coreDataRepo)
        }
    }

    /// Миграция к системе агрегатов категорий
    @MainActor
    private func migrateToAggregateCache() async {
        PerformanceProfiler.start("CategoryAggregate.Migration")

        guard let coreDataRepo = repository as? CoreDataRepository else {
            PerformanceProfiler.end("CategoryAggregate.Migration")
            return
        }

        // ИСПРАВЛЕНИЕ: Проверить что есть транзакции для миграции
        // Если allTransactions пустой (данные не загрузились или потерялись),
        // миграция с пустым массивом вызовет зависание UI
        guard !allTransactions.isEmpty else {
            // Нет транзакций - нечего мигрировать, отметить миграцию как завершенную
            UserDefaults.standard.set(1, forKey: "aggregateCacheVersion")
            PerformanceProfiler.end("CategoryAggregate.Migration")
            return
        }

        // Построить агрегаты из всех транзакций в фоновом потоке
        await aggregateCache.rebuildFromTransactions(
            allTransactions,
            baseCurrency: appSettings.baseCurrency,
            repository: coreDataRepo
        )

        // Отметить миграцию как завершенную
        UserDefaults.standard.set(1, forKey: "aggregateCacheVersion")

        PerformanceProfiler.end("CategoryAggregate.Migration")
    }

    /// Rebuild aggregate cache after CSV import
    /// Called by CSVImportService to ensure category sums are up-to-date
    func rebuildAggregateCacheAfterImport() async {
        guard let coreDataRepo = repository as? CoreDataRepository else { return }

        await aggregateCache.rebuildFromTransactions(
            allTransactions,
            baseCurrency: appSettings.baseCurrency,
            repository: coreDataRepo
        )
    }

    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }
    
    var filteredTransactions: [Transaction] {
        var transactions = applyRules(to: allTransactions)

        if let selectedCategories = selectedCategories {
            transactions = filterService.filterByCategories(transactions, categories: selectedCategories)
        }

        return filterRecurringTransactions(transactions)
    }
    
    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        let transactions = applyRules(to: allTransactions)
        return filterService.filterByTimeRange(transactions, start: range.start, end: range.end)
    }
    
    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        let transactions = applyRules(to: allTransactions)

        return filterService.filterByTimeAndCategory(
            transactions,
            series: recurringSeries,
            start: range.start,
            end: range.end,
            categories: selectedCategories
        )
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
        let (recurring, regular) = filterService.separateRecurringTransactions(transactions)
        let nearestRecurring = groupingService.getNearestRecurringTransactions(recurring)
        transactions = regular + nearestRecurring

        if let accountId = accountId {
            transactions = filterService.filterByAccount(transactions, accountId: accountId)
        }
        
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let searchNumber = Double(searchText.replacingOccurrences(of: ",", with: "."))
            // PERFORMANCE: Use cached dictionary instead of creating new one on each search
            let accountsById = getAccountsById()
            
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
        // Delegated to groupingService for cleaner code and better maintainability
        return groupingService.groupByDate(transactions)
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
        if !cacheManager.summaryCacheInvalidated, let cached = cacheManager.cachedSummary {
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
        
        cacheManager.cachedSummary = result
        cacheManager.summaryCacheInvalidated = false
        
        PerformanceProfiler.end("summary.calculation.sync")
        return result
    }
    
    func categoryExpenses(timeFilterManager: TimeFilterManager) -> [String: CategoryExpense] {
        // Проверить кеш
        if !cacheManager.categoryExpensesCacheInvalidated,
           let cached = cacheManager.cachedCategoryExpenses {
            return cached
        }

        // Использовать кеш агрегатов для эффективного расчета
        let result = aggregateCache.getCategoryExpenses(
            timeFilter: timeFilterManager.currentFilter,
            baseCurrency: appSettings.baseCurrency
        )

        cacheManager.cachedCategoryExpenses = result
        cacheManager.categoryExpensesCacheInvalidated = false

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
                accountName: transaction.accountName,
                targetAccountName: transaction.targetAccountName,
                targetCurrency: transaction.targetCurrency,
                targetAmount: transaction.targetAmount,
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
            // НЕ вызываем invalidateCaches(), recalculateAccountBalances() и saveToStorage() напрямую
            // Но ставим флаги для отложенного выполнения в endBatch()
            if isBatchMode {
                pendingBalanceRecalculation = true
                pendingSave = true
            }
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
            }
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        // Заполняем названия счетов если они еще не заполнены
        let accountName = transaction.accountName ?? (transaction.accountId.flatMap { accountId in
            accounts.first(where: { $0.id == accountId })?.name
        })
        let targetAccountName = transaction.targetAccountName ?? (transaction.targetAccountId.flatMap { targetAccountId in
            accounts.first(where: { $0.id == targetAccountId })?.name
        })

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
                accountName: accountName,
                targetAccountName: targetAccountName,
                targetCurrency: transaction.targetCurrency,
                targetAmount: transaction.targetAmount,
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
                accountName: accountName,
                targetAccountName: targetAccountName,
                targetCurrency: transaction.targetCurrency,
                targetAmount: transaction.targetAmount,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        }
        
        let transactionsWithRules = applyRules(to: [transactionWithID])
        let existingIDs = Set(allTransactions.map { $0.id })
        
        if !existingIDs.contains(transactionWithID.id) {
            createCategoriesForTransactions(transactionsWithRules)
            insertTransactionsSorted(transactionsWithRules)

            // КРИТИЧЕСКИ ВАЖНО: Для счетов из accountsWithCalculatedInitialBalance и депозитов
            // нужно напрямую обновить баланс, так как recalculateAccountBalances() пропустит их транзакции
            // Этот метод теперь также корректно обрабатывает депозиты в internal transfers
            applyTransactionToBalancesDirectly(transactionWithID)

            // Инкрементальное обновление кеша агрегатов
            aggregateCache.updateForTransaction(
                transaction: transactionWithID,
                operation: .add,
                baseCurrency: appSettings.baseCurrency
            )

            invalidateCaches()
            scheduleBalanceRecalculation()
            scheduleSave()
        } else {
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
                    targetCurrency: allTransactions[i].targetCurrency,
                    targetAmount: allTransactions[i].targetAmount,
                    recurringSeriesId: allTransactions[i].recurringSeriesId,
                    recurringOccurrenceId: allTransactions[i].recurringOccurrenceId,
                    createdAt: allTransactions[i].createdAt
                )
            }
        }

        invalidateCaches()
        saveToStorageDebounced()
    }

    func clearHistory() {
        allTransactions = []
        categoryRules = []
        accounts = []
        saveToStorage() // Keep immediate save for critical operations
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
        
    }
    
    func deleteTransaction(_ transaction: Transaction) {

        // removeAll уже создает новый массив, что правильно триггерит @Published
        allTransactions.removeAll { $0.id == transaction.id }

        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        // КРИТИЧЕСКИ ВАЖНО: Удаляем затронутые аккаунты из Set,
        // чтобы их балансы были пересчитаны с новым списком транзакций
        if let accountId = transaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = transaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }

        // Инкрементальное обновление кеша агрегатов
        aggregateCache.updateForTransaction(
            transaction: transaction,
            operation: .delete,
            baseCurrency: appSettings.baseCurrency
        )

        invalidateCaches()
        scheduleBalanceRecalculation()

        scheduleSave()
        
    }

    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }

        // Заполняем названия счетов если они еще не заполнены
        let accountName = transaction.accountName ?? (transaction.accountId.flatMap { accountId in
            accounts.first(where: { $0.id == accountId })?.name
        })
        let targetAccountName = transaction.targetAccountName ?? (transaction.targetAccountId.flatMap { targetAccountId in
            accounts.first(where: { $0.id == targetAccountId })?.name
        })

        // Создаем обновленную транзакцию с названиями счетов
        var updatedTransaction = transaction
        if accountName != nil && updatedTransaction.accountName == nil {
            updatedTransaction = Transaction(
                id: updatedTransaction.id,
                date: updatedTransaction.date,
                description: updatedTransaction.description,
                amount: updatedTransaction.amount,
                currency: updatedTransaction.currency,
                convertedAmount: updatedTransaction.convertedAmount,
                type: updatedTransaction.type,
                category: updatedTransaction.category,
                subcategory: updatedTransaction.subcategory,
                accountId: updatedTransaction.accountId,
                targetAccountId: updatedTransaction.targetAccountId,
                accountName: accountName,
                targetAccountName: targetAccountName,
                targetCurrency: updatedTransaction.targetCurrency,
                targetAmount: updatedTransaction.targetAmount,
                recurringSeriesId: updatedTransaction.recurringSeriesId,
                recurringOccurrenceId: updatedTransaction.recurringOccurrenceId,
                createdAt: updatedTransaction.createdAt
            )
        }

        // КРИТИЧЕСКИ ВАЖНО: Удаляем затронутые аккаунты из Set,
        // чтобы их балансы были пересчитаны с новым списком транзакций
        let oldTransaction = allTransactions[index]
        if let accountId = oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }
        // Также удаляем новые аккаунты, если они изменились
        if let accountId = updatedTransaction.accountId, accountId != oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = updatedTransaction.targetAccountId, targetAccountId != oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }

        // Создаем новый массив вместо модификации элемента на месте
        var newTransactions = allTransactions
        newTransactions[index] = updatedTransaction

        // Переприсваиваем весь массив для триггера @Published
        allTransactions = newTransactions

        // Инкрементальное обновление кеша агрегатов
        aggregateCache.updateForTransaction(
            transaction: updatedTransaction,
            operation: .update(oldTransaction: oldTransaction),
            baseCurrency: appSettings.baseCurrency
        )

        invalidateCaches()
        scheduleBalanceRecalculation()
        scheduleSave()
    }

    // MARK: - Custom Categories

    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    // MARK: - Accounts

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

        // Сохраняем конвертированные суммы при создании перевода
        // convertedAmount — сумма в валюте источника (если отличается от currency)
        // targetAmount / targetCurrency — сумма в валюте получателя
        let sourceAccount = newAccounts[sourceIndex]
        let convertedAmountForSource: Double? = (currency != sourceAccount.currency) ? amount : nil
        let resolvedTargetCurrency = newAccounts[targetIndex].currency

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmountForSource,
            type: .internalTransfer,
            category: String(localized: "transactionForm.transfer"),
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId,
            accountName: newAccounts[sourceIndex].name,
            targetAccountName: newAccounts[targetIndex].name,
            targetCurrency: resolvedTargetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )

        insertTransactionsSorted([transferTx])
        
        accountBalanceService.syncAccountBalances(accounts)

        saveToStorageDebounced()
    }

    // MARK: - Helper Methods

    private func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        guard !newTransactions.isEmpty else { return }

        // ОПТИМИЗАЦИЯ: Заменен O(n²) алгоритм вставки на O(n log n) сортировку
        // Вместо вставки каждой транзакции в отсортированный массив (O(n) поиск + O(n) insert),
        // просто добавляем все транзакции и сортируем весь массив один раз
        // Для 10,000 транзакций: 100,000,000 операций → 140,000 операций (ускорение в 60-80 раз)
        allTransactions.append(contentsOf: newTransactions)
        allTransactions.sort { $0.date > $1.date }
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
                    targetCurrency: transaction.targetCurrency,
                    targetAmount: transaction.targetAmount,
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

            let transactions = await MainActor.run { self.allTransactions }
            let rules = await MainActor.run { self.categoryRules }
            let accs = await MainActor.run { self.accounts }
            let categories = await MainActor.run { self.customCategories }
            let series = await MainActor.run { self.recurringSeries }
            let occurrences = await MainActor.run { self.recurringOccurrences }

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

            PerformanceProfiler.end("saveToStorage")
        }
    }

    /// Debounced version of saveToStorage to prevent excessive saves
    /// Delays save operation by 500ms after last change
    /// Use this instead of saveToStorage() for operations that may trigger multiple times
    func saveToStorageDebounced() {
        saveDebouncer?.cancel()
        saveDebouncer = Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveToStorage()
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

    /// Синхронизирует список счетов из AccountsViewModel и сохраняет состояние.
    /// Заменяет повторяющийся паттерн:
    /// ```
    /// transactionsViewModel.accounts = accountsViewModel.accounts
    /// transactionsViewModel.recalculateAccountBalances()
    /// transactionsViewModel.saveToStorage()
    /// ```
    func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) {
        accounts = accountsViewModel.accounts
        recalculateAccountBalances()
        saveToStorage()
    }

    // MARK: - Синхронные методы сохранения для импорта

    private func saveTransactionsSync(_ transactions: [Transaction]) {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveTransactionsSync(transactions)
            } catch {
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
            } catch {
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
            } catch {
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
                    // Source: используем convertedAmount
                    balance -= tx.convertedAmount ?? tx.amount
                } else if tx.targetAccountId == accountId {
                    // Target: используем targetAmount
                    balance += tx.targetAmount ?? tx.convertedAmount ?? tx.amount
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Skip deposit transactions for regular accounts
                break
            }
        }
        
        return balance
    }
    
    private func loadFromStorage() async {

        // OPTIMIZATION: Load recent transactions first for fast UI display
        let now = Date()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .month, value: -displayMonthsRange, to: now) else {
            // Fallback to loading all transactions
            allTransactions = repository.loadTransactions(dateRange: nil)
            displayTransactions = allTransactions
            hasOlderTransactions = false
            loadOtherData()
            return
        }

        let recentDateRange = DateInterval(start: startDate, end: now)

        // Load recent transactions for UI (fast)
        displayTransactions = repository.loadTransactions(dateRange: recentDateRange)

        // Load ALL transactions synchronously in background to ensure data is ready before migration
        // CRITICAL FIX: Use .value to wait for completion so allTransactions is populated
        // before initializeCategoryAggregates() runs
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let allTxns = self.repository.loadTransactions(dateRange: nil)

            await MainActor.run {
                self.allTransactions = allTxns
                self.hasOlderTransactions = allTxns.count > self.displayTransactions.count

                if self.hasOlderTransactions {
                }

                // Recalculate caches with full data
                self.invalidateCaches()
                self.rebuildIndexes()
            }
        }.value

        loadOtherData()
    }
    
    private func loadOtherData() {
        categoryRules = repository.loadCategoryRules()
        
        // Load accounts from AccountBalanceService (single source of truth)
        accounts = accountBalanceService.accounts
        
        // Note: Initial balances will be calculated after ALL transactions are loaded
        // This happens asynchronously in the background task above
        
        customCategories = repository.loadCategories()
        recurringSeries = repository.loadRecurringSeries()
        recurringOccurrences = repository.loadRecurringOccurrences()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        
        // Calculate initial balances with displayTransactions for now
        // Will be recalculated when all transactions load in background
        for account in accounts {
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
            }
        }

        // NOTE: Do NOT call recalculateAccountBalances() here!
        // Balances are already calculated and saved in Core Data.
        // They will be recalculated when all transactions finish loading in background

        // PERFORMANCE: Do NOT call rebuildIndexes() here!
        // At this point allTransactions is still empty (loading in background task).
        // Indexes will be built when background task completes (see loadFromStorage Task).

        // Precompute currency conversions in background for better UI performance
        precomputeCurrencyConversions()
    }
    
    /// Load older transactions beyond the initial display range
    /// Call this when user scrolls to the bottom or requests to view older data
    func loadOlderTransactions() {
        guard hasOlderTransactions else {
            return
        }
        
        
        // displayTransactions should now include all transactions
        displayTransactions = allTransactions
        hasOlderTransactions = false
        
    }
    
    /// Reset and recalculate all account balances from scratch
    /// This is useful when balances are corrupted (e.g., from double-counting transactions)
    /// Call this method from Settings to fix balance issues
    func resetAndRecalculateAllBalances() {
        
        // STEP 1: Clear all cached initial balances
        let oldInitialBalances = initialAccountBalances
        initialAccountBalances = [:]
        
        // STEP 2: Recalculate initial balances (starting capital without any transactions)
        // Initial balance = current balance - sum of all transactions
        for account in accounts {
            let transactionsSum = calculateTransactionsBalance(for: account.id)
            let initialBalance = account.balance - transactionsSum
            initialAccountBalances[account.id] = initialBalance

            _ = oldInitialBalances[account.id]
        }

        // STEP 3: Recalculate current balances from scratch
        recalculateAccountBalances()
        
        // STEP 4: Save to storage
        saveToStorage()
        
    }

    // MARK: - Initial Balance Access

    /// Получить начальный баланс счета (вычисленный при импорте или установленный вручную)
    /// - Parameter accountId: ID счета
    /// - Returns: Начальный баланс или nil если не установлен
    func getInitialBalance(for accountId: String) -> Double? {
        // Приоритет: локальный кэш -> BalanceCalculationService
        if let localBalance = initialAccountBalances[accountId] {
            return localBalance
        }
        return balanceCalculationService.getInitialBalance(for: accountId)
    }

    /// Проверить, является ли счет импортированным (с автоматически рассчитанным начальным балансом)
    /// - Parameter accountId: ID счета
    /// - Returns: true если счет был импортирован и его транзакции уже учтены в балансе
    func isAccountImported(_ accountId: String) -> Bool {
        // Проверяем оба источника для обратной совместимости
        return accountsWithCalculatedInitialBalance.contains(accountId) ||
               balanceCalculationService.isImported(accountId)
    }

    /// Сбросить все флаги импортированных счетов
    /// Используйте с осторожностью - это приведет к пересчету всех балансов
    func resetImportedAccountFlags() {
        accountsWithCalculatedInitialBalance.removeAll()
        balanceCalculationService.clearImportedFlags()
    }

    /// Применяет транзакцию к балансам счетов напрямую
    /// Используется для счетов из accountsWithCalculatedInitialBalance,
    /// где recalculateAccountBalances() пропускает транзакции
    private func applyTransactionToBalancesDirectly(_ transaction: Transaction) {
        var newAccounts = accounts
        var balanceChanged = false

        switch transaction.type {
        case .income:
            if let accountId = transaction.accountId,
               accountsWithCalculatedInitialBalance.contains(accountId),
               let index = newAccounts.firstIndex(where: { $0.id == accountId }) {
                // Используем targetAmount если валюта операции отличается от валюты счета
                let amount: Double
                if let targetAmount = transaction.targetAmount,
                   let targetCurrency = transaction.targetCurrency,
                   targetCurrency == newAccounts[index].currency {
                    amount = targetAmount
                } else {
                    amount = transaction.amount
                }
                newAccounts[index].balance += amount
                balanceChanged = true
            }

        case .expense:
            if let accountId = transaction.accountId,
               accountsWithCalculatedInitialBalance.contains(accountId),
               let index = newAccounts.firstIndex(where: { $0.id == accountId }) {
                // Используем targetAmount если валюта операции отличается от валюты счета
                let amount: Double
                if let targetAmount = transaction.targetAmount,
                   let targetCurrency = transaction.targetCurrency,
                   targetCurrency == newAccounts[index].currency {
                    amount = targetAmount
                } else {
                    amount = transaction.amount
                }
                newAccounts[index].balance -= amount
                balanceChanged = true
            }

        case .internalTransfer:
            // Списание со счета-источника
            if let sourceId = transaction.accountId,
               let sourceIndex = newAccounts.firstIndex(where: { $0.id == sourceId }) {
                let sourceAccount = newAccounts[sourceIndex]
                // Source: используем convertedAmount, записанный при создании
                let sourceAmount = transaction.convertedAmount ?? transaction.amount

                if sourceAccount.isDeposit, var sourceDepositInfo = sourceAccount.depositInfo {
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
                    newAccounts[sourceIndex].depositInfo = sourceDepositInfo
                    var totalBalance: Decimal = sourceDepositInfo.principalBalance
                    if !sourceDepositInfo.capitalizationEnabled {
                        totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                    balanceChanged = true
                } else if accountsWithCalculatedInitialBalance.contains(sourceId) {
                    newAccounts[sourceIndex].balance -= sourceAmount
                    balanceChanged = true
                }
            }

            // Зачисление на счет-получатель
            if let targetId = transaction.targetAccountId,
               let targetIndex = newAccounts.firstIndex(where: { $0.id == targetId }) {
                let targetAccount = newAccounts[targetIndex]
                // Target: используем targetAmount, записанный при создании
                let targetAmount = transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount

                // Обрабатываем депозиты отдельно - нужно обновить depositInfo
                if targetAccount.isDeposit, var targetDepositInfo = targetAccount.depositInfo {
                    let amountDecimal = Decimal(targetAmount)
                    targetDepositInfo.principalBalance += amountDecimal
                    newAccounts[targetIndex].depositInfo = targetDepositInfo
                    var totalBalance: Decimal = targetDepositInfo.principalBalance
                    if !targetDepositInfo.capitalizationEnabled {
                        totalBalance += targetDepositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                    balanceChanged = true
                } else if accountsWithCalculatedInitialBalance.contains(targetId) {
                    // Обычный счет из импорта
                    newAccounts[targetIndex].balance += targetAmount
                    balanceChanged = true
                }
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            // Эти типы обрабатываются через специальные методы депозитов
            break
        }

        if balanceChanged {
            accounts = newAccounts
            // Синхронизируем с AccountsViewModel
            accountBalanceService.syncAccountBalances(accounts)
        }
    }

    func recalculateAccountBalances() {
        guard !accounts.isEmpty else {
            return
        }

        // OPTIMIZATION: Skip recalculation if nothing changed since last calculation
        if !cacheManager.balanceCacheInvalidated && cacheManager.lastBalanceCalculationTransactionCount == allTransactions.count {
            return
        }

        currencyConversionWarning = nil
        var balanceChanges: [String: Double] = [:]

        // ОПТИМИЗАЦИЯ: Создать Set из ID существующих счетов для быстрой проверки O(1)
        let existingAccountIds = Set(accounts.map { $0.id })

        // ОПТИМИЗАЦИЯ: Создать Dictionary для O(1) lookups счетов по ID
        // Вместо accounts.first(where:) (O(n)) используем accountsById[id] (O(1))
        // Для 10,000 транзакций × 25 счетов: 250,000 lookups → ускорение в 5-10 раз
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        // Рассчитываем initialBalance для НОВЫХ аккаунтов
        for account in accounts {
            balanceChanges[account.id] = 0
            if initialAccountBalances[account.id] == nil {
                // Проверяем, есть ли initialBalance от AccountBalanceService (ручное создание счета)
                if let manualInitialBalance = accountBalanceService.getInitialBalance(for: account.id) {
                    // Счет был создан вручную - используем его начальный баланс
                    // НЕ добавляем в accountsWithCalculatedInitialBalance - транзакции ДОЛЖНЫ обрабатываться!
                    initialAccountBalances[account.id] = manualInitialBalance

                    // Синхронизируем с BalanceCalculationService - отмечаем как manual
                    balanceCalculationService.markAsManual(account.id)
                    balanceCalculationService.setInitialBalance(manualInitialBalance, for: account.id)
                } else {
                    // Проверяем, есть ли уже транзакции для этого счета
                    let transactionsSum = calculateTransactionsBalance(for: account.id)

                    // КРИТИЧЕСКИ ВАЖНО: Различаем два сценария:
                    // 1. Счет создан при импорте CSV с balance=0 - транзакции ДОЛЖНЫ применяться
                    // 2. Счет импортирован с существующим balance>0 - транзакции уже учтены

                    if account.balance == 0 && transactionsSum != 0 {
                        // Сценарий 1: Новый счет созданный при импорте CSV
                        // Initial balance = 0, транзакции должны применяться для расчета баланса
                        initialAccountBalances[account.id] = 0
                        // НЕ добавляем в accountsWithCalculatedInitialBalance - транзакции ДОЛЖНЫ обрабатываться!

                        // Синхронизируем с BalanceCalculationService - отмечаем как manual (транзакции применяются)
                        balanceCalculationService.markAsManual(account.id)
                        balanceCalculationService.setInitialBalance(0, for: account.id)
                    } else {
                        // Сценарий 2: Счет с существующим балансом (импортирован с данными)
                        // Рассчитываем initialBalance = balance - транзакции
                        // Транзакции УЖЕ УЧТЕНЫ в current balance
                        let initialBalance = account.balance - transactionsSum
                        initialAccountBalances[account.id] = initialBalance
                        accountsWithCalculatedInitialBalance.insert(account.id)

                        // Синхронизируем с BalanceCalculationService
                        balanceCalculationService.markAsImported(account.id)
                        balanceCalculationService.setInitialBalance(initialBalance, for: account.id)
                    }
                }
            }
        }

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        let hasConversionIssues = false

        for tx in allTransactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    // Пропустить транзакции удаленных счетов
                    guard existingAccountIds.contains(accountId) else { continue }
                    guard !accountsWithCalculatedInitialBalance.contains(accountId) else { continue }
                    // Используем targetAmount если валюта операции отличается от валюты счета
                    let amountToUse: Double
                    if let targetAmount = tx.targetAmount,
                       let targetCurrency = tx.targetCurrency,
                       let account = accountsById[accountId],  // ОПТИМИЗАЦИЯ: O(1) lookup
                       targetCurrency == account.currency {
                        amountToUse = targetAmount
                    } else {
                        amountToUse = tx.amount
                    }
                    balanceChanges[accountId, default: 0] += amountToUse
                }
            case .expense:
                if let accountId = tx.accountId {
                    // Пропустить транзакции удаленных счетов
                    guard existingAccountIds.contains(accountId) else { continue }
                    guard !accountsWithCalculatedInitialBalance.contains(accountId) else { continue }
                    // Используем targetAmount если валюта операции отличается от валюты счета
                    let amountToUse: Double
                    if let targetAmount = tx.targetAmount,
                       let targetCurrency = tx.targetCurrency,
                       let account = accountsById[accountId],  // ОПТИМИЗАЦИЯ: O(1) lookup
                       targetCurrency == account.currency {
                        amountToUse = targetAmount
                    } else {
                        amountToUse = tx.amount
                    }
                    balanceChanges[accountId, default: 0] -= amountToUse
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break
            case .internalTransfer:
                if let sourceId = tx.accountId {
                    // Пропустить если source счет удален
                    guard existingAccountIds.contains(sourceId) else {
                        // Если source удален, не обрабатываем весь перевод
                        continue
                    }
                    guard !accountsWithCalculatedInitialBalance.contains(sourceId) else {
                        // Source пропускаем, но обрабатываем target ниже
                        if let targetId = tx.targetAccountId,
                           existingAccountIds.contains(targetId),
                           !accountsWithCalculatedInitialBalance.contains(targetId) {
                            let resolvedTargetAmount = tx.targetAmount ?? tx.convertedAmount ?? tx.amount
                            balanceChanges[targetId, default: 0] += resolvedTargetAmount
                        }
                        continue
                    }
                    // Source: используем convertedAmount, записанный при создании
                    let sourceAmount = tx.convertedAmount ?? tx.amount
                    balanceChanges[sourceId, default: 0] -= sourceAmount
                }

                if let targetId = tx.targetAccountId {
                    // Пропустить если target счет удален
                    guard existingAccountIds.contains(targetId) else { continue }
                    guard !accountsWithCalculatedInitialBalance.contains(targetId) else { continue }
                    // Target: используем targetAmount, записанный при создании
                    let resolvedTargetAmount = tx.targetAmount ?? tx.convertedAmount ?? tx.amount
                    balanceChanges[targetId, default: 0] += resolvedTargetAmount
                }
            }
        }

        // Удалить orphaned balance changes для несуществующих счетов
        balanceChanges = balanceChanges.filter { accountId, _ in
            existingAccountIds.contains(accountId)
        }

        // Создаем новый массив вместо модификации элементов на месте
        // Это необходимо для корректной работы @Published property wrapper
        var newAccounts = accounts

        for index in newAccounts.indices {
            let accountId = newAccounts[index].id

            if newAccounts[index].isDeposit {
                if let depositInfo = newAccounts[index].depositInfo {
                    var totalBalance: Decimal = depositInfo.principalBalance
                    if !depositInfo.capitalizationEnabled {
                        totalBalance += depositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[index].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                }
            } else {
                let initialBalance = initialAccountBalances[accountId] ?? newAccounts[index].balance
                let changes = balanceChanges[accountId] ?? 0
                newAccounts[index].balance = initialBalance + changes
            }
        }

        // Переприсваиваем весь массив для триггера @Published
        accounts = newAccounts

        // Синхронизируем обновленные балансы с AccountBalanceService
        accountBalanceService.syncAccountBalances(accounts)

        // Сохраняем обновленные балансы в Core Data
        accountBalanceService.saveAllAccountsSync()

        if hasConversionIssues {
            currencyConversionWarning = "Не удалось конвертировать валюты для некоторых переводов. Балансы могут быть неточными. Проверьте подключение к интернету."
        }

        // OPTIMIZATION: Update cache state after successful calculation
        cacheManager.balanceCacheInvalidated = false
        cacheManager.lastBalanceCalculationTransactionCount = allTransactions.count
        cacheManager.cachedAccountBalances = balanceChanges
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
        saveToStorageDebounced()
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

            saveToStorageDebounced()
            generateRecurringTransactions()
        }
    }

    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            recurringSeries[index].isActive = false
            saveToStorageDebounced()
        }
    }
    
    /// Останавливает recurring-серию и удаляет все будущие транзакции/occurrences.
    /// Извлечён из TransactionCard для соблюдения SRP.
    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String) {
        stopRecurringSeries(seriesId)

        let dateFormatter = DateFormatters.dateFormatter
        guard let txDate = dateFormatter.date(from: transactionDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())

        // Удаляем все будущие транзакции этой серии
        let futureOccurrences = recurringOccurrences.filter { occurrence in
            guard occurrence.seriesId == seriesId,
                  let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                return false
            }
            return occurrenceDate > txDate && occurrenceDate > today
        }

        for occurrence in futureOccurrences {
            allTransactions.removeAll { $0.id == occurrence.transactionId }
            recurringOccurrences.removeAll { $0.id == occurrence.id }
        }

        recalculateAccountBalances()
        saveToStorage()
    }

    /// Очистить внутреннее состояние для удаленного счета
    func cleanupDeletedAccount(_ accountId: String) {
        initialAccountBalances.removeValue(forKey: accountId)
        accountsWithCalculatedInitialBalance.remove(accountId)

        // Очистить кеш балансов
        cacheManager.cachedAccountBalances.removeValue(forKey: accountId)

        // Инвалидировать кеш балансов для пересчета
        cacheManager.balanceCacheInvalidated = true
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        if deleteTransactions {
            // CRITICAL: Delete all transactions associated with this series
            _ = allTransactions.filter { $0.recurringSeriesId == seriesId }

            // Remove transactions
            allTransactions.removeAll { $0.recurringSeriesId == seriesId }
        } else {
            // Clear the recurring series link, transactions become regular
            var updatedTransactions: [Transaction] = []
            for transaction in allTransactions {
                if transaction.recurringSeriesId == seriesId {
                    var updatedTransaction = transaction
                    // Create new transaction without recurring IDs
                    updatedTransaction = Transaction(
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
                        accountName: transaction.accountName,
                        targetAccountName: transaction.targetAccountName,
                        targetCurrency: transaction.targetCurrency,
                        targetAmount: transaction.targetAmount,
                        recurringSeriesId: nil,
                        recurringOccurrenceId: nil,
                        createdAt: transaction.createdAt
                    )
                    updatedTransactions.append(updatedTransaction)
                } else {
                    updatedTransactions.append(transaction)
                }
            }
            allTransactions = updatedTransactions
        }

        // Remove occurrences
        recurringOccurrences.removeAll { $0.seriesId == seriesId }

        // Remove series
        recurringSeries.removeAll { $0.id == seriesId }

        // CRITICAL: Recalculate balances after deleting transactions
        invalidateCaches()
        rebuildIndexes()
        scheduleBalanceRecalculation()

        scheduleSave()

        // Cancel notifications
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
            saveToStorageDebounced()

            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
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
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Step 1: Delete all FUTURE transactions for this series
        _ = allTransactions.filter { transaction in
            guard transaction.recurringSeriesId == seriesId else { return false }
            guard let date = DateFormatters.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return date > today
        }.count
        
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
        generateRecurringTransactions()
        
        // Step 4: Recalculate balances
        invalidateCaches()
        rebuildIndexes()
        scheduleBalanceRecalculation()
        
        // Step 5: Save
        scheduleSave()
        
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

        // Skip if no active recurring series
        if recurringSeries.filter({ $0.isActive }).isEmpty {
            return
        }

        // Delegate generation to recurringGenerator service
        let existingTransactionIds = Set(allTransactions.map { $0.id })
        let (newTransactions, newOccurrences) = recurringGenerator.generateTransactions(
            series: recurringSeries,
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            horizonMonths: 3
        )
        
        // First, insert new transactions if any
        if !newTransactions.isEmpty {
            insertTransactionsSorted(newTransactions)
            recurringOccurrences.append(contentsOf: newOccurrences)
        }

        // Now convert past recurring transactions to regular transactions
        // This must happen AFTER insertion to catch newly created transactions with past dates
        let updatedAllTransactions = recurringGenerator.convertPastRecurringToRegular(allTransactions)
        let convertedCount = zip(allTransactions, updatedAllTransactions).filter { $0.0.recurringSeriesId != $0.1.recurringSeriesId }.count

        // Reassign to trigger @Published if conversions happened
        let needsSave = !newTransactions.isEmpty || convertedCount > 0
        if convertedCount > 0 {
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
                        targetCurrency: updatedTransaction.targetCurrency,
                        targetAmount: updatedTransaction.targetAmount,
                        recurringSeriesId: updatedTransaction.recurringSeriesId,
                        recurringOccurrenceId: updatedTransaction.recurringOccurrenceId,
                        createdAt: updatedTransaction.createdAt
                    )
                    allTransactions[index] = updatedTransaction
                }
            }
        }

        saveToStorageDebounced()
    }

    // MARK: - Subcategories

    /// Get subcategories linked to a specific transaction (O(1) index lookup)
    /// Note: CRUD operations for subcategories should use CategoriesViewModel
    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = cacheManager.getSubcategoryIds(for: transactionId)
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    // MARK: - Cached Lookups (delegated to TransactionCacheManager)

    private func getAccountsById() -> [String: Account] {
        cacheManager.getAccountsById(accounts: accounts)
    }

    // MARK: - Transaction Indexes

    func rebuildIndexes() {
        cacheManager.rebuildIndexes(transactions: allTransactions)
        cacheManager.buildSubcategoryIndex(links: transactionSubcategoryLinks)
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
        isBatchMode = true
        pendingBalanceRecalculation = false
        pendingSave = false
    }
    
    /// End batch mode and perform all pending operations
    /// This will recalculate balances and save if needed
    func endBatch() {
        isBatchMode = false

        var operationsPerformed: [String] = []

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            operationsPerformed.append("balance recalc")
            pendingBalanceRecalculation = false
        }

        if pendingSave {
            saveToStorage()
            operationsPerformed.append("save")
            pendingSave = false
        }

        // Refresh displayTransactions after batch operations to ensure UI is updated
        refreshDisplayTransactions()

        if operationsPerformed.isEmpty {
        } else {
        }
    }

    /// End batch mode without automatic save (caller handles save)
    /// Used by CSV import to avoid double-save (endBatch's async save + explicit sync save)
    func endBatchWithoutSave() {
        isBatchMode = false

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        // Skip save - caller will do sync save for data safety
        pendingSave = false

        // Refresh displayTransactions after batch operations to ensure UI is updated
        refreshDisplayTransactions()
    }

    /// Refresh displayTransactions from allTransactions
    /// Call this after bulk operations (CSV import, delete all, etc.)
    /// to ensure UI displays the latest data
    func refreshDisplayTransactions() {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -displayMonthsRange, to: now) else {
            displayTransactions = allTransactions
            hasOlderTransactions = false
            return
        }

        let startDateString = Self.dateFormatter.string(from: startDate)
        displayTransactions = allTransactions.filter { $0.date >= startDateString }
        hasOlderTransactions = allTransactions.count > displayTransactions.count
    }

    /// Helper method to schedule balance recalculation
    /// In batch mode, this is delayed until endBatch()
    /// In normal mode, this is executed immediately
    private func scheduleBalanceRecalculation() {
        if isBatchMode {
            pendingBalanceRecalculation = true
        } else {
            recalculateAccountBalances()
        }
    }
    
    /// Helper method to schedule save
    /// In batch mode, this is delayed until endBatch()
    /// In normal mode, this uses debounced save to prevent excessive I/O
    private func scheduleSave() {
        if isBatchMode {
            pendingSave = true
        } else {
            saveToStorageDebounced()
        }
    }

    // MARK: - Currency Conversion (delegated to TransactionCurrencyService)

    func precomputeCurrencyConversions() {
        currencyService.precompute(transactions: allTransactions, baseCurrency: appSettings.baseCurrency)
    }

    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        currencyService.getConvertedAmount(transactionId: transactionId, to: baseCurrency)
    }

    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        currencyService.getConvertedAmountOrCompute(transaction: transaction, to: baseCurrency)
    }
}

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
