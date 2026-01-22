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

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository

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
