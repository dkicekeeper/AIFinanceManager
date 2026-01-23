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

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private lazy var migrationService = DataMigrationService()
    private var migrationCompleted = false

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol? = nil) {
        self.repository = repository ?? CoreDataRepository()
        print("🗄️ [APP_COORDINATOR] Using repository: CoreDataRepository")

        // Initialize ViewModels in dependency order
        // 1. Accounts (no dependencies)
        self.accountsViewModel = AccountsViewModel(repository: repository)

        // 2. Categories (no dependencies)
        self.categoriesViewModel = CategoriesViewModel(repository: repository)

        // 3. Subscriptions (no dependencies on other ViewModels)
        self.subscriptionsViewModel = SubscriptionsViewModel(repository: repository)

        // 4. Deposits (depends on Accounts)
        self.depositsViewModel = DepositsViewModel(repository: repository, accountsViewModel: accountsViewModel)

        // 5. Transactions (depends on Accounts and Categories)
        self.transactionsViewModel = TransactionsViewModel(repository: repository)

        // Set up bidirectional dependency between TransactionsViewModel and AccountsViewModel
        self.transactionsViewModel.accountsViewModel = accountsViewModel

        // CRITICAL: Подписываемся на изменения всех дочерних ViewModels
        // Это гарантирует, что AppCoordinator будет уведомлять SwiftUI о любых изменениях
        setupViewModelObservers()

        // Note: TransactionsViewModel still needs access to other ViewModels for some operations
        // This will be refactored in Phase 6
    }

    // MARK: - Public Methods
    
    private var isInitialized = false
    
    /// Initialize all ViewModels asynchronously
    /// Should be called once after AppCoordinator is created
    func initialize() async {
        // Prevent double initialization
        guard !isInitialized else {
            print("⏭️ [APP_COORDINATOR] Already initialized, skipping")
            return
        }
        
        isInitialized = true
        print("🚀 [APP_COORDINATOR] Starting initialization")
        PerformanceProfiler.start("AppCoordinator.initialize")
        
        // STEP 1: Check and perform migration if needed
        if migrationService.isMigrationNeeded() {
            print("🔄 [APP_COORDINATOR] Starting data migration...")
            do {
                try await migrationService.migrateAllData()
                migrationCompleted = true
                print("✅ [APP_COORDINATOR] Migration completed")
                
                // Reload all ViewModels after migration
                print("🔄 [APP_COORDINATOR] Reloading ViewModels after migration...")
                accountsViewModel.reloadFromStorage()
                categoriesViewModel.reloadFromStorage()
            } catch {
                print("❌ [APP_COORDINATOR] Migration failed: \(error)")
                // Continue with UserDefaults fallback
            }
        } else {
            print("✅ [APP_COORDINATOR] Data already migrated")
            migrationCompleted = true
        }
        
        // STEP 2: Load data asynchronously - this is non-blocking
        await transactionsViewModel.loadDataAsync()
        
        PerformanceProfiler.end("AppCoordinator.initialize")
        print("✅ [APP_COORDINATOR] Initialization complete")
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
}
