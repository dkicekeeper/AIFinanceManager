//
//  AppCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Coordinator for managing ViewModel dependencies and initialization

import Foundation
import SwiftUI
import CoreData
import Observation

/// Coordinator that manages all ViewModels and their dependencies
/// Provides a single point of initialization and dependency injection
@Observable
@MainActor
class AppCoordinator {
    // MARK: - Repository

    @ObservationIgnored let repository: DataRepositoryProtocol

    // MARK: - ViewModels

    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    // ✨ Phase 9: Removed SubscriptionsViewModel - recurring operations now in TransactionStore
    @ObservationIgnored let depositsViewModel: DepositsViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let settingsViewModel: SettingsViewModel  // NEW: Phase 1 - Settings refactoring
    @ObservationIgnored let insightsViewModel: InsightsViewModel  // NEW: Phase 17 - Financial Insights

    // MARK: - New Architecture (Phase 7)

    /// NEW 2026-02-05: TransactionStore - Single Source of Truth for transactions
    /// ✨ Phase 9: Now includes recurring operations (subscriptions + recurring transactions)
    /// Replaces multiple services: TransactionCRUDService, CategoryAggregateService, etc.
    @ObservationIgnored let transactionStore: TransactionStore

    // MARK: - Coordinators

    // ✨ Phase 9: Removed RecurringTransactionCoordinator - operations now in TransactionStore

    /// REFACTORED 2026-02-02: Single entry point for balance operations
    /// Phase 1-4: Foundation completed - Store, Engine, Queue, Cache, Coordinator
    @ObservationIgnored let balanceCoordinator: BalanceCoordinator

    // MARK: - Private Properties

    private var isInitialized = false
    private var isFastPathStarted = false

    // Observable loading stage outputs — views bind to these for per-element skeletons
    private(set) var isFastPathDone = false       // accounts + categories ready (~50ms)
    private(set) var isFullyInitialized = false   // transactions + all data ready (~1-3s)

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol? = nil) {
        self.repository = repository ?? CoreDataRepository()

        // Initialize ViewModels in dependency order
        // 1. Accounts (no dependencies)
        self.accountsViewModel = AccountsViewModel(repository: self.repository)

        // 2. REFACTORED 2026-02-02: Initialize BalanceCoordinator FIRST
        // This is the Single Source of Truth for all balances
        // Created before TransactionsViewModel to avoid circular dependencies
        self.balanceCoordinator = BalanceCoordinator(
            repository: self.repository,
            cacheManager: nil  // Will be set later after TransactionsViewModel is created
        )

        // 3. Transactions (MIGRATED: now independent, uses BalanceCoordinator)
        // Create first to access currencyService and appSettings
        self.transactionsViewModel = TransactionsViewModel(repository: self.repository)

        // 3.1 NEW 2026-02-05: Initialize TransactionStore
        // Single Source of Truth for all transaction operations
        // UPDATED 2026-02-05 Phase 7.1: Added balanceCoordinator for automatic balance updates
        // ✨ UPDATED 2026-02-09 Phase 9: Now includes recurring operations with LRU cache
        self.transactionStore = TransactionStore(
            repository: self.repository,
            balanceCoordinator: self.balanceCoordinator,
            cacheCapacity: 1000
        )

        // 3. Categories (depends on TransactionsViewModel for currency conversion)
        self.categoriesViewModel = CategoriesViewModel(
            repository: self.repository,
            currencyService: transactionsViewModel.currencyService,
            appSettings: transactionsViewModel.appSettings
        )

        // ✨ Phase 9: Removed SubscriptionsViewModel initialization - recurring now in TransactionStore

        // 5. Deposits (depends on Accounts)
        self.depositsViewModel = DepositsViewModel(repository: self.repository, accountsViewModel: accountsViewModel)

        // ✨ Phase 9: Removed RecurringTransactionCoordinator initialization - operations now in TransactionStore

        // 7. REFACTORED 2026-02-04: Setup SettingsViewModel (Phase 1)
        // Initialize Settings services with Protocol-Oriented Design
        let storageService = SettingsStorageService()
        let wallpaperService = WallpaperManagementService()
        let validationService = SettingsValidationService()

        // Initialize coordinators for dangerous operations
        // ✨ Phase 9: Use TransactionStore instead of SubscriptionsViewModel
        let dataResetCoordinator = DataResetCoordinator(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            transactionStore: transactionStore,
            depositsViewModel: depositsViewModel
        )

        let exportCoordinator = ExportCoordinator(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel
        )

        // Phase 2: CSVImportCoordinator will be created lazily in ImportFlowCoordinator
        // because it requires csvFile headers during initialization
        let csvImportCoordinator: CSVImportCoordinatorProtocol? = nil

        // Create SettingsViewModel with all dependencies
        self.settingsViewModel = SettingsViewModel(
            storageService: storageService,
            wallpaperService: wallpaperService,
            resetCoordinator: dataResetCoordinator,
            validationService: validationService,
            exportCoordinator: exportCoordinator,
            importCoordinator: csvImportCoordinator,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            initialSettings: transactionsViewModel.appSettings
        )

        // Phase 17: Initialize InsightsService and InsightsViewModel
        let insightsCache = InsightsCache()
        let insightsFilterService = TransactionFilterService(dateFormatter: DateFormatters.dateFormatter)
        let insightsQueryService = TransactionQueryService()

        // Phase 22: Budget spending cache for O(1) period spending lookups
        let budgetSpendingCache = BudgetSpendingCacheService()

        let insightsBudgetService = CategoryBudgetService(
            currencyService: transactionsViewModel.currencyService,
            appSettings: transactionsViewModel.appSettings,
            budgetCache: budgetSpendingCache
        )
        let insightsService = InsightsService(
            transactionStore: self.transactionStore,
            filterService: insightsFilterService,
            queryService: insightsQueryService,
            budgetService: insightsBudgetService,
            cache: insightsCache
        )
        self.insightsViewModel = InsightsViewModel(
            insightsService: insightsService,
            transactionStore: self.transactionStore,
            transactionsViewModel: self.transactionsViewModel
        )

        // @Observable handles change propagation automatically - no manual observer setup needed

        // ✅ CATEGORY REFACTORING: Setup Single Source of Truth for categories
        // TransactionsViewModel subscribes to CategoriesViewModel.categoriesPublisher
        // This eliminates manual sync in 3 places (CategoriesManagementView, deprecated CSVImportService)
        transactionsViewModel.setCategoriesViewModel(categoriesViewModel)

        // ✨ Phase 9: Removed - TransactionStore now handles recurring operations

        // ✅ BALANCE REFACTORING: Inject BalanceCoordinator into ViewModels
        // This establishes Single Source of Truth for balances
        accountsViewModel.balanceCoordinator = balanceCoordinator
        transactionsViewModel.balanceCoordinator = balanceCoordinator
        depositsViewModel.balanceCoordinator = balanceCoordinator

        // Phase 8: Inject TransactionStore into TransactionsViewModel
        // Completes migration to Single Source of Truth for transactions
        transactionsViewModel.transactionStore = transactionStore

        // PHASE 3: Inject TransactionStore into AccountsViewModel and CategoriesViewModel
        // They will observe accounts/categories from TransactionStore instead of owning them
        accountsViewModel.transactionStore = transactionStore
        categoriesViewModel.transactionStore = transactionStore

        // Set coordinator reference in TransactionStore for automatic sync after mutations
        transactionStore.coordinator = self

        // PHASE 3: Setup initial sync from TransactionStore → ViewModels
        // With @Observable, we sync on-demand instead of using Combine subscriptions
        accountsViewModel.setupTransactionStoreObserver()
        categoriesViewModel.setupTransactionStoreObserver()

        // Initial sync from TransactionStore to ViewModels
        syncTransactionStoreToViewModels()

        // ✅ @Observable: No need for Combine observer
        // SwiftUI automatically tracks changes to BalanceCoordinator.balances

    }

    // MARK: - Public Methods

    /// Fast-path startup: loads accounts + categories + settings (<50ms combined).
    /// Call this first so the UI can appear. Full initialization continues via initialize().
    func initializeFastPath() async {
        guard !isFastPathStarted else { return }
        isFastPathStarted = true
        // Load accounts and categories only (small datasets, needed for first frame)
        try? await transactionStore.loadAccountsOnly()
        // NOTE: Calling without transactions so that shouldCalculateFromTransactions accounts
        // briefly show their persisted balance (Phase A). initialize() will pass the full
        // transaction set for Phase B background recalculation.
        await balanceCoordinator.registerAccounts(transactionStore.accounts)
        // Load settings (UserDefaults read — instant)
        await settingsViewModel.loadInitialData()
        isFastPathDone = true
    }

    /// Initialize all ViewModels asynchronously
    /// Should be called once after AppCoordinator is created
    func initialize() async {
        // Prevent double initialization
        guard !isInitialized else {
            return
        }

        isInitialized = true
        PerformanceProfiler.start("AppCoordinator.initialize")

        // Phase 19: Streamlined startup — no duplicate loads
        // 1. Load all data into TransactionStore (single source of truth)
        try? await transactionStore.loadData()

        // 2. Sync subcategory data and invalidate caches (no array copies)
        syncTransactionStoreToViewModels(batchMode: true)

        // 3. Register accounts with BalanceCoordinator.
        // Passing transactions so that shouldCalculateFromTransactions accounts
        // are recalculated from scratch (CoreData `balance` field is unreliable
        // for these accounts since persistBalance() is async Task.detached).
        await balanceCoordinator.registerAccounts(
            transactionStore.accounts,
            transactions: transactionStore.transactions
        )
        isFullyInitialized = true

        // 4. Generate recurring transactions in background (non-blocking)
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.transactionsViewModel.generateRecurringTransactions()
        }

        // 5. Load settings (only if fast path hasn't already loaded them)
        if !isFastPathStarted {
            await settingsViewModel.loadInitialData()
        }

        // Phase 22: Rebuild persistent aggregates if CoreData is missing them.
        // Runs in background — doesn't block startup. On subsequent launches the
        // aggregates are already built and maintained incrementally via apply().
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let txCount = await self.transactionStore.transactions.count
            let currency = await self.transactionStore.baseCurrency
            let allTx = await self.transactionStore.transactions

            // Check if aggregates exist; rebuild only if CoreData is empty
            let existingMonthly = await self.transactionStore.monthlyAggregateService.fetchLast(
                1, currency: currency
            )
            if existingMonthly.first?.transactionCount == 0 && txCount > 0 {
                await self.transactionStore.categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
                await self.transactionStore.monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
            }
        }

        // Phase 19: Removed transactionsViewModel.loadDataAsync() — was duplicating TransactionStore work
        // (generateRecurringAsync + loadAggregateCacheAsync which was a no-op)

        // Purge persistent history older than 7 days — prevents unbounded DB growth
        Task(priority: .background) {
            CoreDataStack.shared.purgeHistory(olderThan: 7)
        }

        PerformanceProfiler.end("AppCoordinator.initialize")
    }
    
    // MARK: - Private Methods

    /// REMOVED: setupViewModelObservers() - not needed with @Observable
    /// @Observable automatically notifies SwiftUI of changes, no manual propagation needed

    /// Phase 16: Lightweight sync — no array copies needed
    /// With computed properties, ViewModels read directly from TransactionStore.
    /// This method now only handles cache invalidation and insights.
    /// - Parameter batchMode: When true, skips insights recompute (for CSV imports, bulk operations)
    func syncTransactionStoreToViewModels(batchMode: Bool = false) {
        // Phase 16: No array copies — ViewModels use computed properties from TransactionStore
        // Only invalidate caches that derived computations depend on
        self.transactionsViewModel.invalidateCaches()

        // Sync subcategory data to CategoriesViewModel (not yet computed properties)
        self.categoriesViewModel.syncCategoriesFromStore()

        // Phase 18: Push-model — invalidate cache and schedule background recompute
        if !batchMode {
            self.insightsViewModel.invalidateAndRecompute()
        }
    }
}
