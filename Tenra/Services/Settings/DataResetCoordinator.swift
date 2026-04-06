//
//  DataResetCoordinator.swift
//  Tenra
//
//  Created on 2026-02-04
//

import Foundation

/// Coordinator for dangerous data operations
/// Centralizes reset and recalculation logic that affects multiple ViewModels
@MainActor
final class DataResetCoordinator: DataResetCoordinatorProtocol {
    // MARK: - Dependencies (weak to prevent retain cycles)

    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var accountsViewModel: AccountsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var transactionStore: TransactionStore?
    private weak var depositsViewModel: DepositsViewModel?

    init(
        transactionsViewModel: TransactionsViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        transactionStore: TransactionStore? = nil,
        depositsViewModel: DepositsViewModel? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.transactionStore = transactionStore
        self.depositsViewModel = depositsViewModel
    }

    // MARK: - DataResetCoordinatorProtocol

    func resetAllData() async throws {

        guard let transactionsViewModel = transactionsViewModel else {
            throw DataResetError.viewModelNotAvailable("TransactionsViewModel")
        }

        guard let accountsViewModel = accountsViewModel else {
            throw DataResetError.viewModelNotAvailable("AccountsViewModel")
        }

        guard let categoriesViewModel = categoriesViewModel else {
            throw DataResetError.viewModelNotAvailable("CategoriesViewModel")
        }

        guard let transactionStore = transactionStore else {
            throw DataResetError.viewModelNotAvailable("TransactionStore")
        }

        do {
            // Reset transactions (includes accounts)
            transactionsViewModel.resetAllData()

            // Reload ViewModels that have reload methods
            accountsViewModel.reloadFromStorage()
            categoriesViewModel.reloadFromStorage()

            // Reload TransactionStore to clear recurring data
            try await transactionStore.loadData()

            // @Observable handles UI updates automatically - no need for objectWillChange.send()

        } catch {
            throw DataResetError.resetFailed(underlying: error)
        }
    }

    func recalculateAllBalances() async throws {

        guard let transactionsViewModel = transactionsViewModel else {
            throw DataResetError.viewModelNotAvailable("TransactionsViewModel")
        }

        guard let accountsViewModel = accountsViewModel else {
            throw DataResetError.viewModelNotAvailable("AccountsViewModel")
        }

        // Recalculate all balances from transactions
        transactionsViewModel.resetAndRecalculateAllBalances()

        // Reload accounts to get updated balances
        accountsViewModel.reloadFromStorage()

        // @Observable handles UI updates automatically

    }

    // MARK: - Dependency Injection

    func setDependencies(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        transactionStore: TransactionStore,
        depositsViewModel: DepositsViewModel
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.transactionStore = transactionStore
        self.depositsViewModel = depositsViewModel
    }
}
