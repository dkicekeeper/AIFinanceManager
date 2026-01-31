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

    var initialAccountBalances: [String: Double] = []

    // MARK: - CRUD Service (Phase 1 Refactoring)

    /// Service responsible for Create, Update, Delete operations
    /// Extracted to follow Single Responsibility Principle
    private lazy var crudService: TransactionCRUDServiceProtocol = {
        TransactionCRUDService(delegate: self)
    }()

    // MARK: - Balance Coordinator (Phase 1.2 Refactoring)

    /// Service responsible for coordinating balance calculations
    /// Extracted to eliminate duplication with AccountsViewModel and follow SRP
    private lazy var balanceCoordinator: TransactionBalanceCoordinatorProtocol = {
        TransactionBalanceCoordinator(delegate: self)
    }()

    // MARK: - Storage Coordinator (Phase 1.3 Refactoring)

    /// Service responsible for save/load operations
    /// Extracted to follow Single Responsibility Principle
    private lazy var storageCoordinator: TransactionStorageCoordinatorProtocol = {
        TransactionStorageCoordinator(delegate: self)
    }()

    // MARK: - Recurring Transaction Service (Phase 1.4 Refactoring)

    /// Service responsible for recurring transaction operations
    /// Extracted to follow Single Responsibility Principle
    private lazy var recurringService: RecurringTransactionServiceProtocol = {
        RecurringTransactionService(delegate: self)
    }()

    // MARK: - Balance Calculation Service

    /// Service for unified balance calculation logic
    /// Manages imported account tracking and provides consistent balance calculation
    private let balanceCalculationService: BalanceCalculationServiceProtocol

    /// Координатор для сериализации операций с балансами
    /// Предотвращает race conditions при одновременном обновлении балансов
    private let balanceUpdateCoordinator = BalanceUpdateCoordinatorWrapper()

    /// Tracks accounts with auto-calculated initial balances (imported accounts)
    /// For these accounts, transactions should not be processed twice
    var accountsWithCalculatedInitialBalance: Set<String> = []

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
    var isBatchMode = false
    var pendingBalanceRecalculation = false
    var pendingSave = false

    // MARK: - Notification Processing Guard

    /// Prevents concurrent processing of recurring series notifications
    /// This avoids race conditions when multiple notifications arrive simultaneously
    private var isProcessingRecurringNotification = false

    func invalidateCaches() {
        print("🔄 [TransactionsViewModel] Invalidating summary/currency caches (NOT aggregate cache)")
        cacheManager.invalidateAll()
        currencyService.invalidate()
        // NOTE: We do NOT clear aggregate cache here because:
        // - Incremental updates (add/delete/update) already updated it correctly
        // - Clearing it would force unnecessary full rebuild
        // - If full clear needed, caller should use clearAndRebuildAggregateCache()
    }

    /// Clear aggregate cache and trigger full rebuild
    /// Use this when you need to completely rebuild aggregates (e.g., after bulk deletion)
    func clearAndRebuildAggregateCache() {
        print("🔄 [clearAndRebuildAggregateCache] Clearing aggregate cache for full rebuild")
        aggregateCache.clear()

        Task {
            await rebuildAggregateCacheAfterImport()

            // CRITICAL: Invalidate summary cache after rebuild completes
            // This ensures categoryExpenses() fetches fresh data from rebuilt aggregate cache
            await MainActor.run {
                cacheManager.invalidateAll()
                print("🔄 [clearAndRebuildAggregateCache] Summary cache invalidated after rebuild")
            }
        }
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

    /// Rebuild aggregate cache in background (non-blocking, fire-and-forget)
    /// Use this when you need to trigger rebuild from synchronous context
    func rebuildAggregateCacheInBackground() {
        guard let coreDataRepo = repository as? CoreDataRepository else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.aggregateCache.rebuildFromTransactions(
                self.allTransactions,
                baseCurrency: self.appSettings.baseCurrency,
                repository: coreDataRepo
            )

            // CRITICAL: Invalidate summary cache after rebuild completes
            // This ensures categoryExpenses() fetches fresh data from rebuilt aggregate cache
            await MainActor.run { [weak self] in
                self?.cacheManager.invalidateAll()
                print("🔄 [rebuildAggregateCacheInBackground] Summary cache invalidated after rebuild")
            }
        }
    }

    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }
    
    /// Cached transactions with rules applied (invalidated when allTransactions or categoryRules change)
    private var transactionsWithRules: [Transaction] {
        applyRules(to: allTransactions)
    }

    var filteredTransactions: [Transaction] {
        var transactions = transactionsWithRules

        if let selectedCategories = selectedCategories {
            transactions = filterService.filterByCategories(transactions, categories: selectedCategories)
        }

        return filterRecurringTransactions(transactions)
    }

    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        return filterService.filterByTimeRange(transactionsWithRules, start: range.start, end: range.end)
    }

    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()

        return filterService.filterByTimeAndCategory(
            transactionsWithRules,
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
        print("💰 [summary] Called - cacheInvalidated: \(cacheManager.summaryCacheInvalidated)")

        // Return cached summary if valid
        if !cacheManager.summaryCacheInvalidated, let cached = cacheManager.cachedSummary {
            print("💰 [summary] Returning cached: income=\(cached.totalIncome), expense=\(cached.totalExpenses)")
            return cached
        }

        print("💰 [summary] Recalculating summary...")

        // Compute synchronously (will be fast with indexes and caching from Phase 2)
        PerformanceProfiler.start("summary.calculation.sync")

        let filtered = transactionsFilteredByTime(timeFilterManager)
        print("💰 [summary] Filtered transactions count: \(filtered.count)")
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

        print("💰 [summary] Calculated: income=\(totalIncome), expense=\(totalExpenses), netFlow=\(totalIncome - totalExpenses)")

        cacheManager.cachedSummary = result
        cacheManager.summaryCacheInvalidated = false
        
        PerformanceProfiler.end("summary.calculation.sync")
        return result
    }
    
    func categoryExpenses(
        timeFilterManager: TimeFilterManager,
        categoriesViewModel: CategoriesViewModel? = nil
    ) -> [String: CategoryExpense] {
        print("📊 [categoryExpenses] Called - cacheInvalidated: \(cacheManager.categoryExpensesCacheInvalidated)")

        // Проверить кеш
        if !cacheManager.categoryExpensesCacheInvalidated,
           let cached = cacheManager.cachedCategoryExpenses {
            print("📊 [categoryExpenses] Returning cached data: \(cached.keys.count) categories")
            return cached
        }

        print("📊 [categoryExpenses] Recalculating from aggregate cache...")

        // CRITICAL FIX: Получить список существующих категорий для фильтрации
        // Это предотвращает отображение удалённых категорий после перезапуска
        let validCategoryNames: Set<String>? = categoriesViewModel.map { vm in
            Set(vm.customCategories.map { $0.name })
        }

        // Использовать кеш агрегатов для эффективного расчета
        let result = aggregateCache.getCategoryExpenses(
            timeFilter: timeFilterManager.currentFilter,
            baseCurrency: appSettings.baseCurrency,
            validCategoryNames: validCategoryNames
        )

        print("📊 [categoryExpenses] Fresh data calculated: \(result.keys.count) categories, total: \(result.values.reduce(0) { $0 + $1.total })")

        cacheManager.cachedCategoryExpenses = result
        cacheManager.categoryExpensesCacheInvalidated = false

        return result
    }
    
    func popularCategories(
        timeFilterManager: TimeFilterManager,
        categoriesViewModel: CategoriesViewModel? = nil
    ) -> [String] {
        let expenses = categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )
        return Array(expenses.keys)
            .sorted { expenses[$0]?.total ?? 0 > expenses[$1]?.total ?? 0 }
    }
    
    var uniqueCategories: [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedUniqueCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in allTransactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }
        let result = Array(categories).sorted()
        cacheManager.cachedUniqueCategories = result
        return result
    }

    var expenseCategories: [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedExpenseCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .expense {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        let result = Array(categories).sorted()
        cacheManager.cachedExpenseCategories = result
        return result
    }

    var incomeCategories: [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedIncomeCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .income {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        let result = Array(categories).sorted()
        cacheManager.cachedIncomeCategories = result
        return result
    }
    
    func addTransactions(_ newTransactions: [Transaction]) {
        // REFACTORED: Delegate to TransactionCRUDService (Phase 1)
        crudService.addTransactions(newTransactions, mode: .regular)

        // Invalidate caches and trigger coordination
        invalidateCaches()
        rebuildIndexes()
        scheduleBalanceRecalculation()
        scheduleSave()
    }
    
    /// Добавляет транзакции для импорта (используйте beginBatch/endBatch для оптимизации)
    /// Example:
    /// ```
    /// viewModel.beginBatch()
    /// viewModel.addTransactionsForImport(transactions)
    /// viewModel.endBatch() // Balance calculation happens once here
    /// ```
    func addTransactionsForImport(_ newTransactions: [Transaction]) {
        // REFACTORED: Delegate to TransactionCRUDService with CSV import mode (Phase 1)
        crudService.addTransactions(newTransactions, mode: .csvImport)

        // НЕ вызываем invalidateCaches(), recalculateAccountBalances() и saveToStorage() напрямую
        // Но ставим флаги для отложенного выполнения в endBatch()
        if isBatchMode {
            pendingBalanceRecalculation = true
            pendingSave = true
        }
    }
    
    // MARK: - Helper Methods (migrated to TransactionCRUDService in Phase 1)
    // formatMerchantName() - REMOVED (now in TransactionCRUDService)
    // matchCategory() - REMOVED (now in TransactionCRUDService)
    // createCategoriesForTransactions() - REMOVED (now in TransactionCRUDService)
    
    func addTransaction(_ transaction: Transaction) {
        // REFACTORED: Delegate to TransactionCRUDService (Phase 1)
        crudService.addTransaction(transaction)

        // REFACTORED: Delegate to TransactionBalanceCoordinator (Phase 1.2)
        // Apply balance changes directly for imported accounts and deposits
        balanceCoordinator.applyTransactionDirectly(transaction)
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
        print("🔄 [resetAllData] Resetting all data")
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

        // CRITICAL: Clear aggregate cache since all transactions are deleted
        aggregateCache.clear()
        print("🔄 [resetAllData] Aggregate cache cleared")

        repository.clearAllData()

        // Принудительно уведомляем об изменении для обновления UI
        objectWillChange.send()

    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // CRITICAL: Remove recurring occurrence if linked
        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        // CRITICAL: Clear calculated balance flags for affected accounts
        // This ensures balances are recalculated after deletion
        if let accountId = transaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
            print("🗑️ [deleteTransaction] Cleared calculated balance flag for account: \(accountId)")
        }
        if let targetAccountId = transaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
            print("🗑️ [deleteTransaction] Cleared calculated balance flag for target account: \(targetAccountId)")
        }

        // REFACTORED: Delegate to TransactionCRUDService (Phase 1)
        crudService.deleteTransaction(transaction)
    }

    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }

        // CRITICAL: Clear calculated balance flags for affected accounts
        // This ensures balances are recalculated with the updated transaction
        let oldTransaction = allTransactions[index]
        if let accountId = oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }
        // Also clear new accounts if they changed
        if let accountId = transaction.accountId, accountId != oldTransaction.accountId {
            accountsWithCalculatedInitialBalance.remove(accountId)
        }
        if let targetAccountId = transaction.targetAccountId, targetAccountId != oldTransaction.targetAccountId {
            accountsWithCalculatedInitialBalance.remove(targetAccountId)
        }

        // REFACTORED: Delegate to TransactionCRUDService (Phase 1)
        crudService.updateTransaction(transaction)
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

    /// Insert transactions into sorted array (by date descending)
    /// NOTE: Also exists in TransactionCRUDService - needed here for transfer() and generateRecurringTransactions()
    private func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        guard !newTransactions.isEmpty else { return }

        // OPTIMIZATION: O(n log n) sort instead of O(n²) insertions
        allTransactions.append(contentsOf: newTransactions)
        allTransactions.sort { $0.date > $1.date }
    }

    /// Apply category rules to transactions
    /// NOTE: Also exists in TransactionCRUDService - needed here for filtered views
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
        // REFACTORED: Delegate to TransactionStorageCoordinator (Phase 1.3)
        storageCoordinator.saveToStorage()
    }

    /// Debounced version of saveToStorage to prevent excessive saves
    /// Delays save operation by 500ms after last change
    /// Use this instead of saveToStorage() for operations that may trigger multiple times
    func saveToStorageDebounced() {
        // REFACTORED: Delegate to TransactionStorageCoordinator (Phase 1.3)
        storageCoordinator.saveToStorageDebounced()
    }

    /// Синхронная версия saveToStorage для использования при импорте
    /// Гарантирует, что все данные сохранены до возврата из функции
    func saveToStorageSync() {
        // REFACTORED: Delegate to TransactionStorageCoordinator (Phase 1.3)
        storageCoordinator.saveToStorageSync()
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


    /// Calculate the balance change for a specific account from all transactions
    /// This is used to determine the initial balance (starting capital) of an account
    /// NOTE: Also exists in TransactionBalanceCoordinator - kept here for resetAndRecalculateAllBalances()
    func calculateTransactionsBalance(for accountId: String) -> Double {
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
        // REFACTORED: Delegate to TransactionStorageCoordinator (Phase 1.3)
        await storageCoordinator.loadFromStorage()
    }

    /// Load older transactions beyond the initial display range
    /// Call this when user scrolls to the bottom or requests to view older data
    func loadOlderTransactions() {
        // REFACTORED: Delegate to TransactionStorageCoordinator (Phase 1.3)
        storageCoordinator.loadOlderTransactions()
    }
    
    /// Reset and recalculate all account balances from scratch
    /// This is useful when balances are corrupted (e.g., from double-counting transactions)
    /// Call this method from Settings to fix balance issues
    func resetAndRecalculateAllBalances() {
        // Invalidate all caches before recalculation
        invalidateCaches()

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

    func recalculateAccountBalances() {
        // REFACTORED: Delegate to TransactionBalanceCoordinator (Phase 1.2)
        // This eliminates ~187 lines of balance calculation logic
        balanceCoordinator.recalculateAllBalances()
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
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        return recurringService.createRecurringSeries(
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
    }
    
    func updateRecurringSeries(_ series: RecurringSeries) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.updateRecurringSeries(series)
    }

    func stopRecurringSeries(_ seriesId: String) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.stopRecurringSeries(seriesId)
    }
    
    /// Останавливает recurring-серию и удаляет все будущие транзакции/occurrences.
    /// Извлечён из TransactionCard для соблюдения SRP.
    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.stopRecurringSeriesAndCleanup(seriesId: seriesId, transactionDate: transactionDate)
    }

    /// Очистить внутреннее состояние для удаленного счета
    func cleanupDeletedAccount(_ accountId: String) {
        initialAccountBalances.removeValue(forKey: accountId)
        accountsWithCalculatedInitialBalance.remove(accountId)

        // Очистить кеш балансов
        cacheManager.cachedAccountBalances.removeValue(forKey: accountId)

        // Инвалидировать кеш балансов для пересчета
        cacheManager.balanceCacheInvalidated = true

        // NOTE: We do NOT invalidate aggregate cache here because:
        // - If only account is deleted (transactions remain), aggregates are still valid
        // - If account+transactions are deleted, caller will invalidate and rebuild
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.deleteRecurringSeries(seriesId, deleteTransactions: deleteTransactions)
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

    func archiveSubscription(_ seriesId: String) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.archiveSubscription(seriesId)
    }
    
    func nextChargeDate(for subscriptionId: String) -> Date? {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        return recurringService.nextChargeDate(for: subscriptionId)
    }
    
    private static var timeFormatter: DateFormatter {
        DateFormatters.timeFormatter
    }
    
    
    func generateRecurringTransactions() {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.generateRecurringTransactions()
    }
    
    func updateRecurringTransaction(_ transactionId: String, updateAllFuture: Bool, newAmount: Decimal? = nil, newCategory: String? = nil, newSubcategory: String? = nil) {
        // REFACTORED: Delegate to RecurringTransactionService (Phase 1.4)
        recurringService.updateRecurringTransaction(
            transactionId,
            updateAllFuture: updateAllFuture,
            newAmount: newAmount,
            newCategory: newCategory,
            newSubcategory: newSubcategory
        )
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
        print("🔚 [endBatchWithoutSave] Starting - allTransactions count: \(allTransactions.count)")
        isBatchMode = false

        if pendingBalanceRecalculation {
            print("🔚 [endBatchWithoutSave] Recalculating account balances")
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        // CRITICAL FIX: Invalidate all caches so UI gets fresh data
        // Without this, categoryExpenses() returns stale cached values
        // and UI shows 0 for category sums after CSV import
        print("🔚 [endBatchWithoutSave] Invalidating caches")
        invalidateCaches()

        // Skip save - caller will do sync save for data safety
        pendingSave = false

        // Refresh displayTransactions after batch operations to ensure UI is updated
        print("🔚 [endBatchWithoutSave] Refreshing display transactions")
        refreshDisplayTransactions()
        print("🔚 [endBatchWithoutSave] Completed - displayTransactions count: \(displayTransactions.count)")
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
        // REFACTORED: Delegate to TransactionBalanceCoordinator (Phase 1.2)
        balanceCoordinator.scheduleRecalculation()
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

// MARK: - TransactionCRUDDelegate Conformance

extension TransactionsViewModel: TransactionCRUDDelegate {
    // All required properties are already defined in the main class
    // No additional implementation needed
}

// MARK: - TransactionBalanceDelegate Conformance

extension TransactionsViewModel: TransactionBalanceDelegate {
    // All required properties are already defined in the main class
    // No additional implementation needed
}

// MARK: - TransactionStorageDelegate Conformance

extension TransactionsViewModel: TransactionStorageDelegate {
    // All required properties are already defined in the main class
    // No additional implementation needed
}

// MARK: - RecurringTransactionServiceDelegate Conformance

extension TransactionsViewModel: RecurringTransactionServiceDelegate {
    // All required properties are already defined in the main class
    // No additional implementation needed
}

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
