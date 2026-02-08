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

    /// Phase 8: TransactionStore as Single Source of Truth for all transaction operations
    /// Replaces legacy CRUD services, cache managers, and coordinators
    var transactionStore: TransactionStore?

    // MARK: - Services (Remaining)

    let currencyService = TransactionCurrencyService()

    /// Phase 8: Minimal cache for read-only display operations
    /// Write operations handled by TransactionStore + UnifiedTransactionCache
    let cacheManager = TransactionCacheManager()

    /// Phase 8: Stub aggregate cache for backward compatibility
    /// Aggregate caching now handled by TransactionStore
    private let aggregateCache: CategoryAggregateCacheProtocol = CategoryAggregateCacheStub()

    private lazy var recurringService: RecurringTransactionServiceProtocol = {
        RecurringTransactionService(delegate: self)
    }()

    private lazy var filterCoordinator: TransactionFilterCoordinatorProtocol = {
        let filterService = TransactionFilterService(dateFormatter: DateFormatters.dateFormatter)
        return TransactionFilterCoordinator(filterService: filterService, dateFormatter: DateFormatters.dateFormatter)
    }()

    private lazy var accountOperationService: AccountOperationServiceProtocol = {
        AccountOperationService()
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
            guard let self = self, let seriesId = notification.userInfo?["seriesId"] as? String else { return }

            #if DEBUG
            print("📨 [TransactionsViewModel] Received .recurringSeriesCreated notification for series: \(seriesId)")
            print("   isProcessingRecurringNotification: \(self.isProcessingRecurringNotification)")
            #endif

            guard !self.isProcessingRecurringNotification else {
                #if DEBUG
                print("⚠️ [TransactionsViewModel] Already processing recurring notification, skipping")
                #endif
                return
            }

            self.isProcessingRecurringNotification = true
            defer { self.isProcessingRecurringNotification = false }

            #if DEBUG
            print("🔄 [TransactionsViewModel] Processing .recurringSeriesCreated notification")
            #endif

            // 🔧 FIX: Only call generateRecurringTransactions() - it handles everything internally
            // RecurringTransactionService already calls scheduleBalanceRecalculation() and scheduleSave() inside
            // Calling them again here causes duplicate balance recalculations
            self.generateRecurringTransactions()
            // Phase 8: Cache invalidation handled by TransactionStore
            self.rebuildIndexes()
            // 🔧 REMOVED: scheduleBalanceRecalculation() - already called in RecurringTransactionService
            // 🔧 REMOVED: scheduleSave() - already called in RecurringTransactionService

            #if DEBUG
            print("✅ [TransactionsViewModel] Finished processing .recurringSeriesCreated notification")
            #endif
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
        // Phase 8: Storage loading handled by TransactionStore
        async let recurringTask = generateRecurringAsync()
        async let aggregatesTask = loadAggregateCacheAsync()

        // Wait for all tasks to complete
        await (recurringTask, aggregatesTask)

        await MainActor.run { isLoading = false }
        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
    }

    /// Generate recurring transactions asynchronously (Phase 2)
    private func generateRecurringAsync() async {
        await MainActor.run {
            self.generateRecurringTransactions()
        }
    }

    /// Load aggregate cache asynchronously
    /// Phase 8: Aggregate caching handled by TransactionStore
    private func loadAggregateCacheAsync() async {
        // Phase 8: Aggregate caching handled by TransactionStore
        // No action needed
        await MainActor.run {
            cacheManager.invalidateCategoryExpenses()
        }
    }

    // MARK: - CRUD Operations (Delegated to Services)

    func addTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot add transaction")
            return
        }

        Task { @MainActor in
            do {
                try await transactionStore.add(transaction)
            } catch {
                print("❌ Failed to add transaction: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTransactions(_ newTransactions: [Transaction]) {
        // Phase 8: Batch add via TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot add transactions")
            return
        }

        Task { @MainActor in
            do {
                for transaction in newTransactions {
                    try await transactionStore.add(transaction)
                }
                // Cache and balance updates handled automatically by TransactionStore
                rebuildIndexes()
            } catch {
                print("❌ Failed to add transactions: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTransactionsForImport(_ newTransactions: [Transaction]) {
        // Phase 8: Import via TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot import transactions")
            return
        }

        Task { @MainActor in
            do {
                for transaction in newTransactions {
                    try await transactionStore.add(transaction)
                }
                // Cache and balance updates handled automatically by TransactionStore
                if isBatchMode {
                    pendingBalanceRecalculation = true
                    pendingSave = true
                }
            } catch {
                print("❌ Failed to import transactions: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot update transaction")
            return
        }

        #if DEBUG
        if let oldTransaction = allTransactions.first(where: { $0.id == transaction.id }) {
            print("📝 [TransactionsViewModel] Updating transaction:")
            print("   Old: \(oldTransaction.amount) \(oldTransaction.currency) - \(oldTransaction.description)")
            print("   New: \(transaction.amount) \(transaction.currency) - \(transaction.description)")
            print("   AccountID: \(oldTransaction.accountId ?? "nil") → \(transaction.accountId ?? "nil")")
        }
        #endif

        Task { @MainActor in
            do {
                try await transactionStore.update(transaction)
            } catch {
                print("❌ Failed to update transaction: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot delete transaction")
            return
        }

        // CRITICAL: Remove recurring occurrence if linked
        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        Task { @MainActor in
            do {
                try await transactionStore.delete(transaction)
            } catch {
                print("❌ Failed to delete transaction: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
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

        saveToStorageDebounced()
    }

    // MARK: - Account Operations (Delegated to AccountOperationService)

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            print("⚠️ TransactionStore not available, cannot transfer")
            return
        }

        guard let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }) else { return }
        let currency = accounts[sourceIndex].currency

        Task { @MainActor in
            do {
                // Convert date string to Date
                let dateFormatter = DateFormatters.dateFormatter
                let dateObj = dateFormatter.date(from: date) ?? Date()

                try await transactionStore.transfer(
                    from: sourceId,
                    to: targetId,
                    amount: amount,
                    currency: currency,
                    date: date,
                    description: description
                )
            } catch {
                print("❌ Failed to transfer: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Queries (Delegated to QueryService)

    func summary(timeFilterManager: TimeFilterManager) -> Summary {
        let filtered = filterCoordinator.filterByTime(
            transactions: allTransactions,
            timeFilter: timeFilterManager.currentFilter
        )

        // IMPORTANT: Always invalidate summary cache because time filtering produces different results
        // The cache doesn't account for time filters, so we need fresh calculation each time
        cacheManager.summaryCacheInvalidated = true

        let result = queryService.calculateSummary(
            transactions: filtered,
            baseCurrency: appSettings.baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        )

        // ✅ FIX: Don't restore invalidation state
        // calculateSummary() already sets it to false after computing the new summary
        // Restoring the old state was breaking the invalidation flow when transactions changed

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
        // Phase 8: Stub aggregate cache - will fall back to transaction calculation
        let result = queryService.getCategoryExpenses(
            timeFilter: timeFilterManager.currentFilter,
            baseCurrency: appSettings.baseCurrency,
            validCategoryNames: validCategoryNames,
            aggregateCache: aggregateCache,  // Phase 8: Stub that returns empty, forces fallback
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
        // ✅ Invalidate category expenses cache when transactions change
        // This is a derived cache computed from aggregates, so it must be cleared
        // to reflect the updated aggregate values after incremental updates
        cacheManager.invalidateCategoryExpenses()
    }

    func rebuildAggregateCacheAfterImport() async {
        // Phase 8: Cache rebuilding handled by TransactionStore automatically
        await MainActor.run { [weak self] in
            self?.cacheManager.invalidateAll()
            self?.notifyDataChanged()
        }
    }

    func rebuildAggregateCacheInBackground() {
        // Phase 8: Cache rebuilding handled by TransactionStore automatically
        Task { @MainActor in
            cacheManager.invalidateAll()
            notifyDataChanged()
        }
    }

    func clearAndRebuildAggregateCache() {
        // Phase 8: Cache rebuilding handled by TransactionStore automatically
        Task { @MainActor in
            cacheManager.invalidateAll()
            notifyDataChanged()
        }
    }

    func precomputeCurrencyConversions() {
        // Phase 8: Currency conversion caching handled by TransactionStore
        // No action needed - conversions computed on-demand
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
        #if DEBUG
        print("🔄 [TransactionsViewModel] scheduleBalanceRecalculation() called")
        print("   📊 State at recalculation:")
        print("      - accounts.count: \(accounts.count)")
        print("      - allTransactions.count: \(allTransactions.count)")
        print("      - balanceCoordinator available: \(balanceCoordinator != nil)")
        #endif

        if let coordinator = balanceCoordinator {
            Task { @MainActor in
                #if DEBUG
                print("🔄 [TransactionsViewModel] Calling coordinator.recalculateAll with:")
                print("      - \(accounts.count) accounts")
                print("      - \(allTransactions.count) transactions")
                for account in accounts.prefix(3) {
                    print("      - Account: \(account.name) (id: \(account.id))")
                }
                #endif

                await coordinator.recalculateAll(
                    accounts: accounts,
                    transactions: allTransactions
                )

                #if DEBUG
                print("✅ [TransactionsViewModel] coordinator.recalculateAll completed")
                #endif
            }
        } else {
            #if DEBUG
            print("⚠️ [TransactionsViewModel] balanceCoordinator is nil!")
            #endif
        }
    }

    func calculateTransactionsBalance(for accountId: String) -> Double {
        // Direct balance access from BalanceCoordinator (O(1))
        return balanceCoordinator?.balances[accountId] ?? 0.0
    }

    func resetAndRecalculateAllBalances() {

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
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func saveToStorageDebounced() {
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func saveToStorageSync() {
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func loadOlderTransactions() {
        // Phase 8: Loading handled by TransactionStore
        // This is a backward compatibility stub
    }

    /// PHASE 3: DEPRECATED - Accounts are now managed by TransactionStore
    /// AccountsViewModel observes TransactionStore.$accounts instead
    /// This method is kept for backward compatibility but does nothing
    func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) {
        #if DEBUG
        print("⚠️ [TransactionsVM] syncAccountsFrom is deprecated - accounts managed by TransactionStore")
        #endif

        // PHASE 3: TransactionStore is Single Source of Truth
        // Accounts are automatically synced via Combine subscription
        // No manual sync needed!
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

                // PHASE 3: No need to sync to TransactionStore
                // CategoriesViewModel already observes TransactionStore.$categories
                // This subscription is kept for backward compatibility with TransactionsViewModel.customCategories

                // Invalidate caches that depend on categories
                self.invalidateCaches()
            }

        // Set initial value
        customCategories = categoriesViewModel.customCategories

        // PHASE 3: No need to sync - CategoriesViewModel observes TransactionStore.$categories
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

// MARK: - Helper Methods

// Phase 9: Standalone helper method (protocol removed with TransactionStorageCoordinator)
extension TransactionsViewModel {
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
