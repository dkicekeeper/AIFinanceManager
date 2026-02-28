//
//  QuickAddCoordinator.swift
//  AIFinanceManager
//
//  Coordinator for QuickAdd transaction flow.
//  Manages category display data preparation and transaction creation.
//

import Foundation
import SwiftUI
import Observation

/// Stable identity for category selection — uses category name, not UUID.
struct CategorySelection: Identifiable {
    var id: String { "\(category)_\(type.rawValue)" }
    let category: String
    let type: TransactionType
}

@Observable
@MainActor
final class QuickAddCoordinator {

    // MARK: - Dependencies

    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionStore: TransactionStore
    private var timeFilterManager: TimeFilterManager
    @ObservationIgnored private let categoryMapper: CategoryDisplayDataMapperProtocol

    // MARK: - Observable State

    var activeSelection: CategorySelection?
    var showingAddCategory = false

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        timeFilterManager: TimeFilterManager,
        categoryMapper: CategoryDisplayDataMapperProtocol? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionStore = transactionStore
        self.timeFilterManager = timeFilterManager
        self.categoryMapper = categoryMapper ?? CategoryDisplayDataMapper()
    }

    // MARK: - Reactive Computed Properties

    /// Categories derived automatically from current filter, transactions, and category data.
    /// @Observable tracks all accessed properties — no manual refresh needed.
    var categories: [CategoryDisplayData] {
        let categoryExpenses = transactionsViewModel.categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )
        return categoryMapper.mapCategories(
            customCategories: categoriesViewModel.customCategories,
            categoryExpenses: categoryExpenses,
            type: .expense,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            currentFilter: timeFilterManager.currentFilter
        )
    }

    // MARK: - Public Methods

    /// Handle category selection
    func handleCategorySelected(_ category: String, type: TransactionType) {
        activeSelection = CategorySelection(category: category, type: type)
        HapticManager.light()
    }

    /// Handle add category action
    func handleAddCategory() {
        showingAddCategory = true
        HapticManager.light()
    }

    /// Handle category added
    func handleCategoryAdded(_ category: CustomCategory) {
        HapticManager.success()
        categoriesViewModel.addCategory(category)
        transactionsViewModel.invalidateCaches()
        showingAddCategory = false
    }

    /// Dismiss current modal
    func dismissModal() {
        activeSelection = nil
    }

    // MARK: - Convenience Computed Properties

    /// Base currency for display
    var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// All accounts
    var accounts: [Account] {
        accountsViewModel.accounts
    }
}
