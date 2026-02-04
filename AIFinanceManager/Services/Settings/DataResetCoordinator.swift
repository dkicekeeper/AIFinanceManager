//
//  DataResetCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation
import Combine

/// Coordinator for dangerous data operations
/// Centralizes reset and recalculation logic that affects multiple ViewModels
@MainActor
final class DataResetCoordinator: DataResetCoordinatorProtocol {
    // MARK: - Dependencies (weak to prevent retain cycles)

    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var accountsViewModel: AccountsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var subscriptionsViewModel: SubscriptionsViewModel?
    private weak var depositsViewModel: DepositsViewModel?

    init(
        transactionsViewModel: TransactionsViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        subscriptionsViewModel: SubscriptionsViewModel? = nil,
        depositsViewModel: DepositsViewModel? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.subscriptionsViewModel = subscriptionsViewModel
        self.depositsViewModel = depositsViewModel
    }

    // MARK: - DataResetCoordinatorProtocol

    func resetAllData() async throws {
        #if DEBUG
        print("🗑️ [DataResetCoordinator] Starting full data reset")
        #endif

        guard let transactionsViewModel = transactionsViewModel else {
            throw DataResetError.viewModelNotAvailable("TransactionsViewModel")
        }

        guard let accountsViewModel = accountsViewModel else {
            throw DataResetError.viewModelNotAvailable("AccountsViewModel")
        }

        guard let categoriesViewModel = categoriesViewModel else {
            throw DataResetError.viewModelNotAvailable("CategoriesViewModel")
        }

        do {
            // Reset transactions (includes accounts)
            transactionsViewModel.resetAllData()

            // Reload ViewModels that have reload methods
            accountsViewModel.reloadFromStorage()
            categoriesViewModel.reloadFromStorage()

            // Trigger UI updates for all ViewModels
            accountsViewModel.objectWillChange.send()
            categoriesViewModel.objectWillChange.send()
            transactionsViewModel.objectWillChange.send()

            // Subscriptions and Deposits will update automatically through ObservableObject
            // No need to reload as they load from repository in init()

            #if DEBUG
            print("✅ [DataResetCoordinator] Data reset completed")
            #endif
        } catch {
            #if DEBUG
            print("❌ [DataResetCoordinator] Reset failed: \(error)")
            #endif
            throw DataResetError.resetFailed(underlying: error)
        }
    }

    func recalculateAllBalances() async throws {
        #if DEBUG
        print("♻️ [DataResetCoordinator] Starting balance recalculation")
        #endif

        guard let transactionsViewModel = transactionsViewModel else {
            throw DataResetError.viewModelNotAvailable("TransactionsViewModel")
        }

        guard let accountsViewModel = accountsViewModel else {
            throw DataResetError.viewModelNotAvailable("AccountsViewModel")
        }

        do {
            // Recalculate all balances from transactions
            transactionsViewModel.resetAndRecalculateAllBalances()

            // Reload accounts to get updated balances
            accountsViewModel.reloadFromStorage()

            // Trigger UI updates
            transactionsViewModel.objectWillChange.send()
            accountsViewModel.objectWillChange.send()

            #if DEBUG
            print("✅ [DataResetCoordinator] Balance recalculation completed")
            #endif
        } catch {
            #if DEBUG
            print("❌ [DataResetCoordinator] Recalculation failed: \(error)")
            #endif
            throw DataResetError.recalculationFailed(underlying: error)
        }
    }

    // MARK: - Dependency Injection

    func setDependencies(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        subscriptionsViewModel: SubscriptionsViewModel,
        depositsViewModel: DepositsViewModel
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.subscriptionsViewModel = subscriptionsViewModel
        self.depositsViewModel = depositsViewModel
    }
}
