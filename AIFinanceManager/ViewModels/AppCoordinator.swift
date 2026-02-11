//
//  AppCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Coordinator for managing ViewModel dependencies and initialization

import Foundation
import SwiftUI
import Combine
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

    private var cancellables = Set<AnyCancellable>()

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

        // CRITICAL: Подписываемся на изменения всех дочерних ViewModels
        // Это гарантирует, что AppCoordinator будет уведомлять SwiftUI о любых изменениях
        setupViewModelObservers()

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

        // PHASE 3: Setup observers for TransactionStore → ViewModels
        // ViewModels observe TransactionStore instead of owning data
        accountsViewModel.setupTransactionStoreObserver()
        categoriesViewModel.setupTransactionStoreObserver()

        // 🔧 CRITICAL FIX: Setup TransactionStore → TransactionsViewModel sync
        // When TransactionStore updates transactions, sync them back to TransactionsViewModel
        setupTransactionStoreObserver()

        // Setup observer for balance updates
        setupBalanceCoordinatorObserver()

        #if DEBUG
        print("✅ [AppCoordinator] Category SSOT established via Combine")
        print("✅ [AppCoordinator] Balance SSOT established via BalanceCoordinator")
        print("✅ [AppCoordinator] TransactionStore SSOT established with sync")
        print("✅ [AppCoordinator] Settings SSOT established via SettingsViewModel (Phase 1)")
        print("✅ [AppCoordinator] PHASE 3: Accounts/Categories SSOT via TransactionStore observers")
        #endif
    }

    // MARK: - Public Methods
    
    private var isInitialized = false
    
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

        // PHASE 3: TransactionStore now owns accounts/categories - they are published to ViewModels
        // No need to sync - ViewModels observe TransactionStore.$accounts and .$categories
        transactionsViewModel.allTransactions = transactionStore.transactions
        transactionsViewModel.displayTransactions = transactionStore.transactions

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

    /// Настройка наблюдателей за изменениями в дочерних ViewModels
    /// Когда любой ViewModel меняется, AppCoordinator уведомляет SwiftUI
    private func setupViewModelObservers() {
        accountsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        transactionsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        categoriesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // ✨ Phase 9: Removed subscriptionsViewModel observer - now using TransactionStore

        depositsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// 🔧 CRITICAL FIX: Setup observer for TransactionStore updates
    /// When TransactionStore updates transactions, sync them back to TransactionsViewModel
    /// This ensures history view and other legacy code sees the new transactions
    private func setupTransactionStoreObserver() {
        transactionStore.$transactions
            .sink { [weak self] updatedTransactions in
                guard let self = self else { return }

                #if DEBUG
                print("🔄 [AppCoordinator] TransactionStore updated: \(updatedTransactions.count) transactions")
                #endif

                // 🔧 CRITICAL FIX: Force SwiftUI to see the change by creating new array
                // Direct assignment might not trigger @Published if it's the same array reference
                self.transactionsViewModel.allTransactions = Array(updatedTransactions)
                self.transactionsViewModel.displayTransactions = Array(updatedTransactions)

                // 🔧 CRITICAL FIX: Invalidate caches when transactions change
                // This ensures category expenses are recalculated with new transactions
                // Fixes bug: category balances not updating in CategoryGridView
                self.transactionsViewModel.invalidateCaches()

                // Trigger UI refresh
                self.transactionsViewModel.notifyDataChanged()
                self.objectWillChange.send()

                #if DEBUG
                print("✅ [AppCoordinator] Synced transactions, invalidated caches, triggered refresh")
                #endif
            }
            .store(in: &cancellables)

        // 🔧 CRITICAL FIX 2026-02-08: Sync accounts from TransactionStore to TransactionsViewModel
        // When TransactionStore updates accounts, sync them to TransactionsViewModel.accounts
        // This fixes the bug where balance recalculation runs with 0 accounts after subscription creation
        transactionStore.$accounts
            .sink { [weak self] updatedAccounts in
                guard let self = self else { return }

                #if DEBUG
                print("🔄 [AppCoordinator] TransactionStore accounts updated: \(updatedAccounts.count) accounts")
                #endif

                // 🔧 CRITICAL: Sync accounts to TransactionsViewModel
                // This ensures scheduleBalanceRecalculation() has correct accounts
                self.transactionsViewModel.accounts = Array(updatedAccounts)

                // Trigger UI refresh
                self.objectWillChange.send()

                #if DEBUG
                print("✅ [AppCoordinator] Synced accounts to TransactionsViewModel")
                #endif
            }
            .store(in: &cancellables)
    }

    /// REFACTORED 2026-02-02: Setup observer for BalanceCoordinator updates
    /// When balances change, sync to Account.balance and notify SwiftUI
    private func setupBalanceCoordinatorObserver() {
        balanceCoordinator.$balances
            .sink { [weak self] updatedBalances in
                guard let self = self else { return }

                // Sync balances from BalanceCoordinator to Account objects
                self.syncBalancesToAccounts(updatedBalances)

                // Notify SwiftUI
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Sync balances from BalanceCoordinator to Account objects
    /// This ensures UI components reading account.balance get updated values
    private func syncBalancesToAccounts(_ balances: [String: Double]) {
        // MIGRATED: Balances are now managed by BalanceCoordinator
        // No need to sync balances to Account.balance field
        // UI components read balances directly from BalanceCoordinator
    }
}
