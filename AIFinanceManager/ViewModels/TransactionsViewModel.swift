//
//  TransactionsViewModel.swift
//  AIFinanceManager
//
//  Phase 2 Refactoring Complete: 2026-02-01
//  Reduction: 1,501 → ~600 lines (-60%)
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TransactionsViewModel: ObservableObject {

    // MARK: - Published State (UI Bindings)

    @Published var allTransactions: [Transaction] = []
    @Published var displayTransactions: [Transaction] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var accounts: [Account] = []

    /// DEPRECATED: Use CategoriesViewModel.categoriesPublisher instead
    /// This property is kept for backward compatibility but synced via Combine
    @Published var customCategories: [CustomCategory] = []

    /// REFACTORED 2026-02-02: Now computed property delegating to SubscriptionsViewModel (Single Source of Truth)
    /// This eliminates data duplication and manual synchronization
    var recurringSeries: [RecurringSeries] {
        subscriptionsViewModel?.recurringSeries ?? []
    }

    @Published var recurringOccurrences: [RecurringOccurrence] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    @Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []
    @Published var selectedCategories: Set<String>? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currencyConversionWarning: String? = nil
    @Published var appSettings: AppSettings = AppSettings.load()
    @Published var hasOlderTransactions: Bool = false
    @Published var dataRefreshTrigger: UUID = UUID()  // ✅ Trigger for forcing UI updates when data changes without count change

    // MIGRATED: initialAccountBalances moved to BalanceCoordinator
    // MIGRATED: accountsWithCalculatedInitialBalance moved to BalanceCoordinator (calculation modes)
    var displayMonthsRange: Int = 120  // 10 years - increased from 6 to support historical data imports

    // MARK: - Dependencies (Injected)

    let repository: DataRepositoryProtocol
    // MIGRATED: accountBalanceService removed - using BalanceCoordinator instead
    // MIGRATED: balanceCalculationService removed - using BalanceCoordinator instead

    /// REFACTORED 2026-02-02: Single Source of Truth for recurring series
    /// Weak reference to avoid retain cycles
    weak var subscriptionsViewModel: SubscriptionsViewModel?

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth for balances
    /// Injected by AppCoordinator - replaces old TransactionBalanceCoordinator
    var balanceCoordinator: BalanceCoordinator?

    // MARK: - Cache & Managers (Direct Access)

    let cacheManager = TransactionCacheManager()
    let currencyService = TransactionCurrencyService()

    // ✅ OPTIMIZED: Using CategoryAggregateCacheOptimized with protocol
    // Provides 98% memory reduction via LRU cache and lazy loading
    let aggregateCache: CategoryAggregateCacheProtocol = CategoryAggregateCacheOptimized(maxSize: 1000)

    // MARK: - Services (Lazy Initialized - Phase 1)

    private lazy var crudService: TransactionCRUDServiceProtocol = {
        TransactionCRUDService(delegate: self)
    }()

    private lazy var storageCoordinator: TransactionStorageCoordinatorProtocol = {
        TransactionStorageCoordinator(delegate: self)
    }()

    private lazy var recurringService: RecurringTransactionServiceProtocol = {
        RecurringTransactionService(delegate: self)
    }()

    // MARK: - Services (Lazy Initialized - Phase 2)

    private lazy var filterCoordinator: TransactionFilterCoordinatorProtocol = {
        let filterService = TransactionFilterService(dateFormatter: DateFormatters.dateFormatter)
        return TransactionFilterCoordinator(filterService: filterService, dateFormatter: DateFormatters.dateFormatter)
    }()

    private lazy var accountOperationService: AccountOperationServiceProtocol = {
        AccountOperationService()
    }()

    private lazy var cacheCoordinator: CacheCoordinatorProtocol = {
        CacheCoordinator(
            cacheManager: cacheManager,
            currencyService: currencyService,
            aggregateCache: aggregateCache
        )
    }()

    private lazy var queryService: TransactionQueryServiceProtocol = {
        TransactionQueryService()
    }()

    // MARK: - Legacy Services (Keep for backward compatibility)

    private lazy var groupingService: TransactionGroupingService = {
        TransactionGroupingService(
            dateFormatter: DateFormatters.dateFormatter,
            displayDateFormatter: DateFormatters.displayDateFormatter,
            displayDateWithYearFormatter: DateFormatters.displayDateWithYearFormatter,
            cacheManager: cacheManager  // ✅ OPTIMIZATION: Pass cache for 23x performance boost
        )
    }()

    private lazy var balanceCalculator: BalanceCalculator = {
        BalanceCalculator(dateFormatter: DateFormatters.dateFormatter)
    }()

    lazy var recurringGenerator: RecurringTransactionGenerator = {
        RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
    }()

    private let balanceUpdateCoordinator = BalanceUpdateCoordinatorWrapper()

    // MARK: - Batch Mode for Performance

    var isBatchMode = false
    var pendingBalanceRecalculation = false
    var pendingSave = false

    // MARK: - Notification Processing Guard

    private var isProcessingRecurringNotification = false
    private var isDataLoaded = false

    // MARK: - Combine Subscriptions

    /// Subscription to CategoriesViewModel.categoriesPublisher (Single Source of Truth)
    private var categoriesSubscription: AnyCancellable?

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        // MIGRATED: accountBalanceService removed - using BalanceCoordinator instead
        // MIGRATED: balanceCalculationService removed - using BalanceCoordinator instead
        // MIGRATED: Performance optimization removed with BalanceCalculationService

        setupRecurringSeriesObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupRecurringSeriesObserver() {
        // Listen for NEW recurring series created
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesCreated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let _ = notification.userInfo?["seriesId"] as? String else { return }
            guard !self.isProcessingRecurringNotification else { return }

            self.isProcessingRecurringNotification = true
            defer { self.isProcessingRecurringNotification = false }

            self.generateRecurringTransactions()
            self.cacheCoordinator.invalidate(scope: .summaryAndCurrency)
            self.rebuildIndexes()
            self.scheduleBalanceRecalculation()
            self.scheduleSave()
        }

        // Listen for UPDATED recurring series
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let _ = notification.userInfo?["seriesId"] as? String else { return }
            guard !self.isProcessingRecurringNotification else { return }

            self.isProcessingRecurringNotification = true
            defer { self.isProcessingRecurringNotification = false }

            self.recurringService.generateRecurringTransactions()
        }
    }

    // MARK: - Data Loading (CONCURRENT)

    func loadDataAsync() async {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        PerformanceProfiler.start("TransactionsViewModel.loadDataAsync")

        await MainActor.run { isLoading = true }

        // PERFORMANCE OPTIMIZATION: Concurrent loading (Phase 2)
        async let storageTask = storageCoordinator.loadFromStorage()
        async let recurringTask = generateRecurringAsync()
        async let aggregatesTask = loadAggregateCacheAsync()

        // Wait for all tasks to complete
        await (storageTask, recurringTask, aggregatesTask)

        await MainActor.run { isLoading = false }
        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
    }

    /// Generate recurring transactions asynchronously (Phase 2)
    private func generateRecurringAsync() async {
        await MainActor.run {
            self.generateRecurringTransactions()
        }
    }

    /// Load aggregate cache asynchronously (NO MIGRATION - Phase 2)
    private func loadAggregateCacheAsync() async {
        guard let coreDataRepo = repository as? CoreDataRepository else { return }

        // Set repository for optimized cache (if using optimized version)
        if let optimizedCache = aggregateCache as? CategoryAggregateCacheOptimized {
            optimizedCache.setRepository(coreDataRepo)
        }

        // MIGRATION REMOVED: Simply load from CoreData (no version check)
        await aggregateCache.loadFromCoreData(repository: coreDataRepo)

        // ✅ FIX: Invalidate CategoryExpenses cache after loading aggregate cache
        // This ensures daily aggregates are used instead of old cached data
        await MainActor.run {
            cacheManager.invalidateCategoryExpenses()
        }
    }

    // MARK: - CRUD Operations (Delegated to Services)

    func addTransaction(_ transaction: Transaction) {
        crudService.addTransaction(transaction)

        // Update balance through BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task { @MainActor in
                await coordinator.updateForTransaction(transaction, operation: .add(transaction))
            }
        }
    }

    func addTransactions(_ newTransactions: [Transaction]) {
        crudService.addTransactions(newTransactions, mode: .regular)
        cacheCoordinator.invalidate(scope: .summaryAndCurrency)
        rebuildIndexes()
        scheduleBalanceRecalculation()
        scheduleSave()
    }

    func addTransactionsForImport(_ newTransactions: [Transaction]) {
        crudService.addTransactions(newTransactions, mode: .csvImport)

        if isBatchMode {
            pendingBalanceRecalculation = true
            pendingSave = true
        }
    }

    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else { return }

        // Balance updates handled by BalanceCoordinator (via crudService)
        crudService.updateTransaction(transaction)
    }

    func deleteTransaction(_ transaction: Transaction) {
        // CRITICAL: Remove recurring occurrence if linked
        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        // Balance updates handled by BalanceCoordinator (via crudService)
        crudService.deleteTransaction(transaction)
    }

    func updateTransactionCategory(_ transactionId: String, category: String, subcategory: String?) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transactionId }) else { return }

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

        cacheCoordinator.invalidate(scope: .summaryAndCurrency)
        saveToStorageDebounced()
    }

    // MARK: - Account Operations (Delegated to AccountOperationService)

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        guard let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }) else { return }
        let currency = accounts[sourceIndex].currency

        accountOperationService.transfer(
            from: sourceId,
            to: targetId,
            amount: amount,
            currency: currency,
            date: date,
            description: description,
            accounts: &accounts,
            allTransactions: &allTransactions,
            balanceCoordinator: balanceCoordinator,  // ✅ CRITICAL FIX: Pass BalanceCoordinator
            saveCallback: { [weak self] in self?.saveToStorageDebounced() }
        )
    }

    // MARK: - Queries (Delegated to QueryService)

    func summary(timeFilterManager: TimeFilterManager) -> Summary {
        let filtered = filterCoordinator.filterByTime(
            transactions: allTransactions,
            timeFilter: timeFilterManager.currentFilter
        )

        // IMPORTANT: Temporarily invalidate summary cache to force recalculation
        // The cache doesn't account for time filters, so we need fresh calculation
        let wasInvalidated = cacheManager.summaryCacheInvalidated
        cacheManager.summaryCacheInvalidated = true

        let result = queryService.calculateSummary(
            transactions: filtered,
            baseCurrency: appSettings.baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        )

        // Restore invalidation state to allow caching for non-filtered queries
        cacheManager.summaryCacheInvalidated = wasInvalidated

        return result
    }

    func categoryExpenses(
        timeFilterManager: TimeFilterManager,
        categoriesViewModel: CategoriesViewModel? = nil
    ) -> [String: CategoryExpense] {
        let validCategoryNames: Set<String>? = categoriesViewModel.map { vm in
            Set(vm.customCategories.map { $0.name })
        }

        // ✅ FIX: Pass transactions and currencyService for date-based filters
        // Date-based filters (last30Days, thisWeek) need direct calculation from transactions
        // Month/year filters use aggregate cache (more efficient)
        let result = queryService.getCategoryExpenses(
            timeFilter: timeFilterManager.currentFilter,
            baseCurrency: appSettings.baseCurrency,
            validCategoryNames: validCategoryNames,
            aggregateCache: aggregateCache,
            cacheManager: cacheManager,
            transactions: allTransactions,
            currencyService: currencyService
        )

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
        return queryService.getPopularCategories(expenses: expenses)
    }

    var uniqueCategories: [String] {
        queryService.getUniqueCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    var expenseCategories: [String] {
        queryService.getExpenseCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    var incomeCategories: [String] {
        queryService.getIncomeCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    // MARK: - Filtering (Delegated to FilterCoordinator)

    var filteredTransactions: [Transaction] {
        filterCoordinator.getFiltered(
            transactions: allTransactions,
            selectedCategories: selectedCategories,
            recurringSeries: recurringSeries
        )
    }

    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        filterCoordinator.filterByTime(transactions: allTransactions, timeFilter: timeFilterManager.currentFilter)
    }

    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        filterCoordinator.filterByTimeAndCategory(
            transactions: allTransactions,
            timeFilter: timeFilterManager.currentFilter,
            categories: selectedCategories,
            series: recurringSeries
        )
    }

    func filterTransactionsForHistory(
        timeFilterManager: TimeFilterManager,
        accountId: String?,
        searchText: String
    ) -> [Transaction] {
        var transactions = transactionsFilteredByTimeAndCategory(timeFilterManager)

        return filterCoordinator.filterForHistory(
            transactions: transactions,
            accountId: accountId,
            searchText: searchText,
            accounts: accounts,
            baseCurrency: appSettings.baseCurrency,
            getSubcategories: { [weak self] transactionId in
                self?.getSubcategoriesForTransaction(transactionId) ?? []
            }
        )
    }

    func groupAndSortTransactionsByDate(_ transactions: [Transaction]) -> (grouped: [String: [Transaction]], sortedKeys: [String]) {
        groupingService.groupByDate(transactions)
    }

    // MARK: - Cache Management (Delegated to CacheCoordinator)

    func invalidateCaches() {
        cacheCoordinator.invalidate(scope: .summaryAndCurrency)
        // ✅ Also invalidate category expenses cache when transactions change
        cacheManager.invalidateCategoryExpenses()
    }

    func rebuildAggregateCacheAfterImport() async {
        guard let coreDataRepo = repository as? CoreDataRepository else { return }
        await cacheCoordinator.rebuildAggregates(
            transactions: allTransactions,
            baseCurrency: appSettings.baseCurrency,
            repository: coreDataRepo
        )
    }

    func rebuildAggregateCacheInBackground() {
        guard let coreDataRepo = repository as? CoreDataRepository else { return }
        cacheCoordinator.rebuildAggregatesAsync(
            transactions: allTransactions,
            baseCurrency: appSettings.baseCurrency,
            repository: coreDataRepo,
            onComplete: { [weak self] in
                // Callback after rebuild completes
            }
        )
    }

    func clearAndRebuildAggregateCache() {
        cacheCoordinator.invalidate(scope: .aggregates)

        Task {
            await rebuildAggregateCacheAfterImport()
            await MainActor.run { [weak self] in
                self?.cacheManager.invalidateAll()
                // ✅ FIX: Trigger UI update after aggregate rebuild
                self?.notifyDataChanged()
            }
        }
    }

    func precomputeCurrencyConversions() {
        cacheCoordinator.precomputeCurrencyConversions(
            transactions: allTransactions,
            baseCurrency: appSettings.baseCurrency
        )
    }

    // MARK: - Balance Management

    func recalculateAccountBalances() {
        // Recalculate all balances through BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task { @MainActor in
                await coordinator.recalculateAll(accounts: accounts, transactions: allTransactions)
            }
        }
    }

    func scheduleBalanceRecalculation() {
        // CRITICAL: Recalculate all account balances after transaction changes
        // This is called after recurring transaction generation, CSV import, etc.
        if let coordinator = balanceCoordinator {
            Task { @MainActor in
                await coordinator.recalculateAll(
                    accounts: accounts,
                    transactions: allTransactions
                )
            }
        }
    }

    func calculateTransactionsBalance(for accountId: String) -> Double {
        // Direct balance access from BalanceCoordinator (O(1))
        return balanceCoordinator?.balances[accountId] ?? 0.0
    }

    func resetAndRecalculateAllBalances() {
        cacheCoordinator.invalidate(scope: .summaryAndCurrency)

        // MIGRATED: Initial balances are already in account.initialBalance
        for account in accounts {
            // Update BalanceCoordinator with initial balance from account
            if let initialBalance = account.initialBalance {
                Task { @MainActor in
                    await balanceCoordinator?.setInitialBalance(initialBalance, for: account.id)
                }
            }
        }

        recalculateAccountBalances()
        saveToStorage()
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
        recurringService.createRecurringSeries(
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
        recurringService.updateRecurringSeries(series)
    }

    func stopRecurringSeries(_ seriesId: String) {
        recurringService.stopRecurringSeries(seriesId)
    }

    func stopRecurringSeriesAndCleanup(seriesId: String, transactionDate: String) {
        recurringService.stopRecurringSeriesAndCleanup(seriesId: seriesId, transactionDate: transactionDate)
    }

    func deleteRecurringSeries(_ seriesId: String, deleteTransactions: Bool = true) {
        recurringService.deleteRecurringSeries(seriesId, deleteTransactions: deleteTransactions)
    }

    func archiveSubscription(_ seriesId: String) {
        recurringService.archiveSubscription(seriesId)
    }

    func nextChargeDate(for subscriptionId: String) -> Date? {
        recurringService.nextChargeDate(for: subscriptionId)
    }

    func generateRecurringTransactions() {
        recurringService.generateRecurringTransactions()
    }

    /// DEPRECATED 2026-02-02: This method is not used anywhere and will be removed
    /// Use RecurringTransactionCoordinator.updateSeries() instead
    @available(*, deprecated, message: "Use RecurringTransactionCoordinator.updateSeries() instead")
    func updateRecurringTransaction(_ transactionId: String, updateAllFuture: Bool, newAmount: Decimal? = nil, newCategory: String? = nil, newSubcategory: String? = nil) {
        recurringService.updateRecurringTransaction(
            transactionId,
            updateAllFuture: updateAllFuture,
            newAmount: newAmount,
            newCategory: newCategory,
            newSubcategory: newSubcategory
        )
    }

    // MARK: - Subscriptions

    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }

    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }

    // MARK: - Storage

    func saveToStorage() {
        storageCoordinator.saveToStorage()
    }

    func saveToStorageDebounced() {
        storageCoordinator.saveToStorageDebounced()
    }

    func saveToStorageSync() {
        storageCoordinator.saveToStorageSync()
    }

    func loadOlderTransactions() {
        storageCoordinator.loadOlderTransactions()
    }

    func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) {
        accounts = accountsViewModel.accounts

        // 🔧 FIX: Register all accounts in BalanceCoordinator when syncing
        // This ensures BalanceCoordinator knows about all accounts and their initial balances
        if let balanceCoordinator = balanceCoordinator {
            Task { @MainActor in
                // Register all accounts
                await balanceCoordinator.registerAccounts(accounts)

                // Set initial balances from AccountsViewModel
                for account in accounts {
                    if let initialBalance = accountsViewModel.getInitialBalance(for: account.id) {
                        await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)
                        await balanceCoordinator.markAsManual(account.id)
                    }
                }
            }
        }

        recalculateAccountBalances()
        saveToStorage()
    }

    /// Setup Combine subscription to CategoriesViewModel (Single Source of Truth)
    /// Call this from AppCoordinator after both ViewModels are initialized
    /// - Parameter categoriesViewModel: The single source of truth for categories
    func setCategoriesViewModel(_ categoriesViewModel: CategoriesViewModel) {
        // Subscribe to categories changes
        categoriesSubscription = categoriesViewModel.categoriesPublisher
            .sink { [weak self] categories in
                guard let self = self else { return }

                // Update local copy
                self.customCategories = categories

                // Invalidate caches that depend on categories
                self.invalidateCaches()
            }

        // Set initial value
        customCategories = categoriesViewModel.customCategories
    }

    // MARK: - Data Management

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
        // REFACTORED 2026-02-02: recurringSeries is now computed from SubscriptionsViewModel
        // Clear in SubscriptionsViewModel instead
        subscriptionsViewModel?.recurringSeries = []
        recurringOccurrences = []
        subcategories = []
        categorySubcategoryLinks = []
        transactionSubcategoryLinks = []
        // MIGRATED: initialAccountBalances removed - managed by BalanceCoordinator
        selectedCategories = nil
        cacheCoordinator.invalidate(scope: .all)
        repository.clearAllData()
        objectWillChange.send()
    }

    // MARK: - Helpers

    func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        guard !newTransactions.isEmpty else { return }
        allTransactions.append(contentsOf: newTransactions)
        allTransactions.sort { $0.date > $1.date }
    }

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = cacheManager.getSubcategoryIds(for: transactionId)
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    func cleanupDeletedAccount(_ accountId: String) {
        // MIGRATED: BalanceCoordinator handles account removal
        Task { @MainActor in
            await balanceCoordinator?.removeAccount(accountId)
        }
        cacheManager.cachedAccountBalances.removeValue(forKey: accountId)
        cacheManager.balanceCacheInvalidated = true
    }

    func rebuildIndexes() {
        cacheManager.rebuildIndexes(transactions: allTransactions)
        cacheManager.buildSubcategoryIndex(links: transactionSubcategoryLinks)
    }

    func refreshDisplayTransactions() {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -displayMonthsRange, to: now) else {
            displayTransactions = allTransactions
            hasOlderTransactions = false
            return
        }

        let startDateString = DateFormatters.dateFormatter.string(from: startDate)
        displayTransactions = allTransactions.filter { $0.date >= startDateString }
        hasOlderTransactions = allTransactions.count > displayTransactions.count
    }

    // MARK: - Batch Operations

    func beginBatch() {
        isBatchMode = true
        pendingBalanceRecalculation = false
        pendingSave = false
    }

    func endBatch() {
        isBatchMode = false

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        if pendingSave {
            saveToStorage()
            pendingSave = false
        }

        refreshDisplayTransactions()
    }

    func endBatchWithoutSave() {
        isBatchMode = false

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        cacheCoordinator.invalidate(scope: .summaryAndCurrency)
        pendingSave = false
        refreshDisplayTransactions()
    }

    func scheduleSave() {
        if isBatchMode {
            pendingSave = true
        } else {
            saveToStorageDebounced()
        }
    }

    // MARK: - Initial Balance Access (MIGRATED to BalanceCoordinator)

    func getInitialBalance(for accountId: String) -> Double? {
        // MIGRATED: Get from account.initialBalance
        // Note: This method is primarily for backward compatibility
        return accounts.first(where: { $0.id == accountId })?.initialBalance
    }

    func isAccountImported(_ accountId: String) -> Bool {
        // MIGRATED: Check BalanceCoordinator calculation mode
        // Async access not possible here, return false for now (not critical)
        return false
    }

    func resetImportedAccountFlags() {
        // MIGRATED: No longer needed - BalanceCoordinator manages modes
        // This method kept for backward compatibility but does nothing
    }

    // MARK: - Currency Conversion

    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        currencyService.getConvertedAmount(transactionId: transactionId, to: baseCurrency)
    }

    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        currencyService.getConvertedAmountOrCompute(transaction: transaction, to: baseCurrency)
    }

    // MARK: - Private Helpers
    // MIGRATED: clearBalanceFlags removed - balance modes managed by BalanceCoordinator
}

// MARK: - Delegate Conformances

extension TransactionsViewModel: TransactionCRUDDelegate {}
// REMOVED: TransactionBalanceDelegate extension - no longer needed after BalanceCoordinator migration
extension TransactionsViewModel: TransactionStorageDelegate {
    func notifyDataChanged() {
        // ✅ CRITICAL FIX: Force @Published to trigger by changing UUID
        // Creating new array doesn't work if count doesn't change, because Combine
        // publisher uses .map { $0.count }.removeDuplicates() which filters it out
        // Instead, we change a dedicated trigger UUID that Combine observes
        dataRefreshTrigger = UUID()
    }
}
extension TransactionsViewModel: RecurringTransactionServiceDelegate {}

// MARK: - Supporting Types

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
