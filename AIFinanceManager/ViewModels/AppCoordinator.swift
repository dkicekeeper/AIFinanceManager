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

        // 3. Transactions (depends on Accounts for balance updates)
        // Create first to access currencyService and appSettings
        // Use Protocol-based DI to prevent silent failures from weak references
        self.transactionsViewModel = TransactionsViewModel(
            repository: self.repository,
            accountBalanceService: accountsViewModel  // AccountsViewModel conforms to AccountBalanceServiceProtocol
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

        // CRITICAL: Подписываемся на изменения всех дочерних ViewModels
        // Это гарантирует, что AppCoordinator будет уведомлять SwiftUI о любых изменениях
        setupViewModelObservers()

        // ✅ CATEGORY REFACTORING: Setup Single Source of Truth for categories
        // TransactionsViewModel subscribes to CategoriesViewModel.categoriesPublisher
        // This eliminates manual sync in 3 places (CategoriesManagementView, CSVImportService)
        transactionsViewModel.setCategoriesViewModel(categoriesViewModel)

        // ✅ RECURRING REFACTORING: Setup Single Source of Truth for recurring series
        // TransactionsViewModel now delegates to SubscriptionsViewModel for recurringSeries
        transactionsViewModel.subscriptionsViewModel = subscriptionsViewModel

        // ✅ BALANCE REFACTORING: Inject BalanceCoordinator into ViewModels
        // This establishes Single Source of Truth for balances
        accountsViewModel.balanceCoordinator = balanceCoordinator
        transactionsViewModel.balanceCoordinator = balanceCoordinator
        depositsViewModel.balanceCoordinator = balanceCoordinator

        // Setup observer for balance updates
        setupBalanceCoordinatorObserver()

        #if DEBUG
        print("✅ [AppCoordinator] Category SSOT established via Combine")
        print("✅ [AppCoordinator] Balance SSOT established via BalanceCoordinator")
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
