//
//  CSVStorageCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for coordinating storage operations during CSV import
/// Handles batch saves, balance recalculation, and finalization
@MainActor
protocol CSVStorageCoordinatorProtocol {
    /// Saves a batch of transactions without triggering expensive operations
    /// - Parameters:
    ///   - transactions: Array of transactions to save
    ///   - subcategoryLinks: Mapping of transaction IDs to subcategory IDs
    ///   - transactionsViewModel: Transactions view model for storage
    ///   - categoriesViewModel: Categories view model for link management
    func saveBatch(
        _ transactions: [Transaction],
        subcategoryLinks: [String: [String]],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async

    /// Finalizes the import process with all expensive operations
    /// Includes balance recalculation, index rebuilding, cache updates, and persistence
    /// - Parameters:
    ///   - accountsViewModel: Accounts view model for balance sync
    ///   - transactionsViewModel: Transactions view model for finalization
    ///   - categoriesViewModel: Categories view model for data sync
    func finalizeImport(
        accountsViewModel: AccountsViewModel?,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async
}
