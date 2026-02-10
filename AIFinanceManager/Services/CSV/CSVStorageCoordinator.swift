//
//  CSVStorageCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 2
//

import Foundation
import Combine

/// Coordinator for storage operations during CSV import
/// Handles batch saves, balance recalculation, and finalization
@MainActor
class CSVStorageCoordinator: CSVStorageCoordinatorProtocol {

    // MARK: - Constants

    private let batchSize = 500

    // MARK: - CSVStorageCoordinatorProtocol

    func saveBatch(
        _ transactions: [Transaction],
        subcategoryLinks: [String: [String]],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async {

        // CRITICAL: Sync categories to TransactionStore BEFORE adding transactions
        // This ensures TransactionStore knows about newly created categories
        if let transactionStore = transactionsViewModel.transactionStore {
            await transactionStore.syncCategories(categoriesViewModel.customCategories)

            // Use batch add for better performance (single persistence operation)
            do {
                try await transactionStore.addBatch(transactions)
            } catch {
                print("❌ Failed to add batch: \(error.localizedDescription)")
            }
        } else {
            // Fallback to old method if TransactionStore not available
            transactionsViewModel.addTransactionsForImport(transactions)
        }

        // Batch link subcategories
        if !subcategoryLinks.isEmpty {
            categoriesViewModel.batchLinkSubcategoriesToTransaction(subcategoryLinks)
        }

        // Memory cleanup
        autoreleasepool {}
    }

    func finalizeImport(
        accountsViewModel: AccountsViewModel?,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async {

        // Finish import mode and persist all changes
        if let transactionStore = transactionsViewModel.transactionStore {
            do {
                try await transactionStore.finishImport()
            } catch {
                print("❌ Failed to finish import: \(error.localizedDescription)")
            }
        }

        // Sync accounts
        if let accountsVM = accountsViewModel {
            transactionsViewModel.accounts = accountsVM.accounts
        }

        // Sync categories
        transactionsViewModel.subcategories = categoriesViewModel.subcategories
        transactionsViewModel.categorySubcategoryLinks = categoriesViewModel.categorySubcategoryLinks
        transactionsViewModel.transactionSubcategoryLinks = categoriesViewModel.transactionSubcategoryLinks

        // Save all category data
        categoriesViewModel.saveAllData()

        // CRITICAL: Force sync save of Core Data context to ensure subcategory links are persisted
        // saveAllData() uses Task.detached which may not complete before app terminates
        do {
            try CoreDataStack.shared.saveContextSync(CoreDataStack.shared.viewContext)
            #if DEBUG
            print("✅ [CSVStorageCoordinator] Forced sync save of subcategory data")
            #endif
        } catch {
            print("❌ [CSVStorageCoordinator] Failed to sync save subcategory data: \(error)")
        }

        // End batch + recalculate balances (without async save)
        transactionsViewModel.endBatchWithoutSave()

        // Rebuild indexes
        transactionsViewModel.rebuildIndexes()

        // Precompute currency conversions
        transactionsViewModel.precomputeCurrencyConversions()

        // Sync balances back to accounts
        if let accountsVM = accountsViewModel {
            syncBalances(from: transactionsViewModel, to: accountsVM)
            accountsVM.saveAllAccountsSync()

            // Register accounts in BalanceCoordinator
            await registerAccountsInBalanceCoordinator(
                accountsVM,
                transactionsViewModel
            )
        }

        // Rebuild aggregate cache
        await transactionsViewModel.rebuildAggregateCacheAfterImport()

        // Notify UI
        transactionsViewModel.objectWillChange.send()
        categoriesViewModel.objectWillChange.send()
        accountsViewModel?.objectWillChange.send()
    }

    // MARK: - Private Helpers

    private func syncBalances(
        from transactionsVM: TransactionsViewModel,
        to accountsVM: AccountsViewModel
    ) {
        // Note: Balance syncing is now handled by BalanceCoordinator
        // No need to manually copy balances between AccountsVM and TransactionsVM
    }

    private func registerAccountsInBalanceCoordinator(
        _ accountsVM: AccountsViewModel,
        _ transactionsVM: TransactionsViewModel
    ) async {
        guard let balanceCoordinator = transactionsVM.balanceCoordinator else { return }

        await balanceCoordinator.registerAccounts(accountsVM.accounts)

        for account in accountsVM.accounts {
            let initialBalance = accountsVM.getInitialBalance(for: account.id) ?? 0
            await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)

            // Mark as manual if not calculating from transactions
            if !account.shouldCalculateFromTransactions {
                await balanceCoordinator.markAsManual(account.id)
            }
        }
    }
}
