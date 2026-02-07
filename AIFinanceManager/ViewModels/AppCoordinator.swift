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

/// Coordinator that manages all ViewModels and their dependencies
/// Provides a single point of initialization and dependency injection
@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - Repository

    let repository: DataRepositoryProtocol

    // MARK: - ViewModels

    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let subscriptionsViewModel: SubscriptionsViewModel
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    let settingsViewModel: SettingsViewModel  // NEW: Phase 1 - Settings refactoring

    // MARK: - New Architecture (Phase 7)

    /// NEW 2026-02-05: TransactionStore - Single Source of Truth for transactions
    /// Replaces multiple services: TransactionCRUDService, CategoryAggregateService, etc.
    let transactionStore: TransactionStore

    // MARK: - Coordinators

    /// REFACTORED 2026-02-02: Single entry point for recurring transaction operations
    let recurringCoordinator: RecurringTransactionCoordinator

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

        // 4. Subscriptions (no dependencies on other ViewModels)
        self.subscriptionsViewModel = SubscriptionsViewModel(repository: self.repository)

        // 5. Deposits (depends on Accounts)
        self.depositsViewModel = DepositsViewModel(repository: self.repository, accountsViewModel: accountsViewModel)

        // 6. REFACTORED 2026-02-02: Setup RecurringTransactionCoordinator
        // Single entry point for all recurring operations
        self.recurringCoordinator = RecurringTransactionCoordinator(
            subscriptionsViewModel: subscriptionsViewModel,
            transactionsViewModel: transactionsViewModel,
            generator: transactionsViewModel.recurringGenerator,
            validator: RecurringValidationService(),
            repository: self.repository
        )

        // 7. REFACTORED 2026-02-04: Setup SettingsViewModel (Phase 1)
        // Initialize Settings services with Protocol-Oriented Design
        let storageService = SettingsStorageService()
        let wallpaperService = WallpaperManagementService()
        let validationService = SettingsValidationService()

        // Initialize coordinators for dangerous operations
        let dataResetCoordinator = DataResetCoordinator(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            subscriptionsViewModel: subscriptionsViewModel,
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

        // ✅ RECURRING REFACTORING: Setup Single Source of Truth for recurring series
        // TransactionsViewModel now delegates to SubscriptionsViewModel for recurringSeries
        transactionsViewModel.subscriptionsViewModel = subscriptionsViewModel

        // ✅ BALANCE REFACTORING: Inject BalanceCoordinator into ViewModels
        // This establishes Single Source of Truth for balances
        accountsViewModel.balanceCoordinator = balanceCoordinator
        transactionsViewModel.balanceCoordinator = balanceCoordinator
        depositsViewModel.balanceCoordinator = balanceCoordinator

        // Phase 8: Inject TransactionStore into TransactionsViewModel
        // Completes migration to Single Source of Truth for transactions
        transactionsViewModel.transactionStore = transactionStore

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

        // 🔧 CRITICAL FIX: Sync data between TransactionStore and TransactionsViewModel
        // This ensures both stores have consistent initial data
        transactionStore.syncAccounts(accountsViewModel.accounts)
        transactionStore.syncCategories(categoriesViewModel.customCategories)
        transactionsViewModel.allTransactions = transactionStore.transactions
        transactionsViewModel.displayTransactions = transactionStore.transactions

        #if DEBUG
        print("🔄 [AppCoordinator] Synced initial data: \(transactionStore.transactions.count) transactions, \(accountsViewModel.accounts.count) accounts")
        #endif

        // REFACTORED 2026-02-02: Register accounts with BalanceCoordinator
        // This initializes the balance store with current account data
        await balanceCoordinator.registerAccounts(accountsViewModel.accounts)

        // CRITICAL: Recalculate balances after loading transactions
        // This ensures accounts with shouldCalculateFromTransactions get correct balances
        #if DEBUG
        print("🔄 [AppCoordinator] Recalculating all balances after initialization...")
        #endif
        await balanceCoordinator.recalculateAll(
            accounts: accountsViewModel.accounts,
            transactions: transactionsViewModel.allTransactions
        )

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

        subscriptionsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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

                // Sync transactions back to TransactionsViewModel for legacy views
                self.transactionsViewModel.allTransactions = updatedTransactions
                self.transactionsViewModel.displayTransactions = updatedTransactions

                // Trigger UI refresh
                self.transactionsViewModel.notifyDataChanged()
                self.objectWillChange.send()
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
