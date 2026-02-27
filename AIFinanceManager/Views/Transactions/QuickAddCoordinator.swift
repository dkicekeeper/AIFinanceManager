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

@Observable
@MainActor
final class QuickAddCoordinator {

    // MARK: - Dependencies

    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionStore: TransactionStore
    @ObservationIgnored private var timeFilterManager: TimeFilterManager
    @ObservationIgnored private let categoryMapper: CategoryDisplayDataMapperProtocol

    // MARK: - Observable State

    private(set) var categories: [CategoryDisplayData] = []
    var selectedCategory: String?
    var selectedType: TransactionType = .expense
    var showingAddCategory = false

    // MARK: - Performance Optimization State

    /// ✅ OPTIMIZATION: Batch mode for CSV imports and bulk operations
    /// When true, skips intermediate UI updates to prevent UI blocking
    var isBatchMode = false

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

        // ✅ OPTIMIZATION: Single update call instead of double (setupBindings + explicit call)
        // With @Observable, no Combine subscriptions needed
        updateCategories()
    }

    /// Call this method when transactions, categories, or filter changes
    /// With @Observable, we refresh on-demand instead of using Combine subscriptions
    func refreshData() {
        updateCategories()
    }

    // MARK: - Public Methods

    /// Update categories with current data
    func updateCategories() {
        // ✅ OPTIMIZATION: Skip updates in batch mode to prevent UI blocking during imports
        guard !isBatchMode else {
            return
        }

        PerformanceProfiler.start("QuickAddCoordinator.updateCategories")

        // Get category expenses from TransactionsViewModel
        let categoryExpenses = transactionsViewModel.categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )

        // Map to display data
        let newCategories = categoryMapper.mapCategories(
            customCategories: categoriesViewModel.customCategories,
            categoryExpenses: categoryExpenses,
            type: .expense,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            currentFilter: timeFilterManager.currentFilter
        )

        categories = newCategories

        PerformanceProfiler.end("QuickAddCoordinator.updateCategories")
    }

    /// Handle category selection
    func handleCategorySelected(_ category: String, type: TransactionType) {
        selectedCategory = category
        selectedType = type
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
        selectedCategory = nil
    }

    /// Update time filter manager.
    /// Call this if the filter manager instance changes after initialization
    /// (e.g., from external injection). No-ops when the same instance is passed.
    func setTimeFilterManager(_ manager: TimeFilterManager) {
        guard timeFilterManager !== manager else { return }
        timeFilterManager = manager
        updateCategories()
    }

    // MARK: - Computed Properties

    /// Base currency for display
    var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// All accounts
    var accounts: [Account] {
        accountsViewModel.accounts
    }
}
