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

    let repository: DataRepositoryProtocol

    // MARK: - ViewModels

    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    // ✨ Phase 9: Removed SubscriptionsViewModel - recurring operations now in TransactionStore
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    let settingsViewModel: SettingsViewModel  // NEW: Phase 1 - Settings refactoring

    // MARK: - New Architecture (Phase 7)

    /// NEW 2026-02-05: TransactionStore - Single Source of Truth for transactions
    /// ✨ Phase 9: Now includes recurring operations (subscriptions + recurring transactions)
    /// Replaces multiple services: TransactionCRUDService, CategoryAggregateService, etc.
    let transactionStore: TransactionStore

    // MARK: - Coordinators

    // ✨ Phase 9: Removed RecurringTransactionCoordinator - operations now in TransactionStore

    /// REFACTORED 2026-02-02: Single entry point for balance operations
    /// Phase 1-4: Foundation completed - Store, Engine, Queue, Cache, Coordinator
    let balanceCoordinator: BalanceCoordinator

    // MARK: - Private Properties

    private var isInitialized = false

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

        #if DEBUG
        print("✅ [AppCoordinator] Category SSOT established via Combine")
        print("✅ [AppCoordinator] Balance SSOT established via BalanceCoordinator")
        print("✅ [AppCoordinator] TransactionStore SSOT established with sync")
        print("✅ [AppCoordinator] Settings SSOT established via SettingsViewModel (Phase 1)")
        print("✅ [AppCoordinator] PHASE 3: Accounts/Categories SSOT via TransactionStore observers")
        #endif
    }

    // MARK: - Public Methods

    /// Initialize all ViewModels asynchronously
    /// Should be called once after AppCoordinator is created
    func initialize() async {
        // Prevent double initialization
        guard !isInitialized else {
            return
        }

        isInitialized = true
        PerformanceProfiler.start("AppCoordinator.initialize")

        // Load data asynchronously - this is non-blocking
        await transactionsViewModel.loadDataAsync()

        // NEW 2026-02-05: Load data into TransactionStore
        try? await transactionStore.loadData()

        // CRITICAL: Sync data from TransactionStore to ViewModels
        // With @Observable, we need to manually sync after data loads
        syncTransactionStoreToViewModels()

        #if DEBUG
        print("✅ [AppCoordinator] TransactionStore loaded: \(transactionStore.transactions.count) transactions, \(transactionStore.accounts.count) accounts, \(transactionStore.categories.count) categories")
        #endif

        // REFACTORED 2026-02-02: Register accounts with BalanceCoordinator
        // This initializes the balance store with current account data
        await balanceCoordinator.registerAccounts(accountsViewModel.accounts)

        // ✅ OPTIMIZED 2026-02-10: No need to recalculate on launch
        // Balances are now persisted to Core Data and loaded correctly during registerAccounts()
        // Only recalculate when truly needed (not on every app launch)
        // Old code: await balanceCoordinator.recalculateAll(accounts, transactions)
        #if DEBUG
        print("✅ [AppCoordinator] Balances loaded from Core Data - skipping recalculation")
        #endif

        // REFACTORED 2026-02-04: Load Settings data (Phase 1)
        #if DEBUG
        print("⚙️ [AppCoordinator] Loading settings data...")
        #endif
        await settingsViewModel.loadInitialData()

        PerformanceProfiler.end("AppCoordinator.initialize")
    }
    
    // MARK: - Private Methods

    /// REMOVED: setupViewModelObservers() - not needed with @Observable
    /// @Observable automatically notifies SwiftUI of changes, no manual propagation needed

    /// Setup manual syncing from TransactionStore to ViewModels
    /// With @Observable, we don't have Combine publishers, so we sync on-demand
    /// This method should be called after TransactionStore updates
    func syncTransactionStoreToViewModels() {
        #if DEBUG
        print("🔄 [AppCoordinator] Syncing TransactionStore to ViewModels")
        print("   Transactions: \(transactionStore.transactions.count)")
        print("   Accounts: \(transactionStore.accounts.count)")
        print("   Categories: \(transactionStore.categories.count)")
        #endif

        // Sync transactions to TransactionsViewModel
        self.transactionsViewModel.allTransactions = Array(transactionStore.transactions)
        self.transactionsViewModel.displayTransactions = Array(transactionStore.transactions)

        // Invalidate caches when transactions change
        self.transactionsViewModel.invalidateCaches()

        // Trigger data changed notification
        self.transactionsViewModel.notifyDataChanged()

        // Sync accounts to TransactionsViewModel
        self.transactionsViewModel.accounts = Array(transactionStore.accounts)

        // Sync accounts to AccountsViewModel
        self.accountsViewModel.syncAccountsFromStore()

        // Sync categories to CategoriesViewModel
        self.categoriesViewModel.syncCategoriesFromStore()

        #if DEBUG
        print("✅ [AppCoordinator] Synced TransactionStore to ViewModels")
        #endif
    }
}
