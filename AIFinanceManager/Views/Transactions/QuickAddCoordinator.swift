//
//  QuickAddCoordinator.swift
//  AIFinanceManager
//
//  Coordinator for QuickAdd transaction flow.
//  Manages category display data preparation and transaction creation.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class QuickAddCoordinator: ObservableObject {

    // MARK: - Dependencies

    // Internal access for temporary exposure during migration
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    private var timeFilterManager: TimeFilterManager
    private let categoryMapper: CategoryDisplayDataMapperProtocol

    // MARK: - Published State

    @Published private(set) var categories: [CategoryDisplayData] = []
    @Published var selectedCategory: String?
    @Published var selectedType: TransactionType = .expense
    @Published var showingAddCategory = false

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        timeFilterManager: TimeFilterManager,
        categoryMapper: CategoryDisplayDataMapperProtocol? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.timeFilterManager = timeFilterManager
        self.categoryMapper = categoryMapper ?? CategoryDisplayDataMapper()

        setupBindings()
        updateCategories()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Combine approach with debounce + distinctUntilChanged
        // Updates only when relevant data changes
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                transactionsViewModel.$allTransactions
                    .map { $0.count }
                    .removeDuplicates(),
                categoriesViewModel.$customCategories
                    .map { $0.count }
                    .removeDuplicates(),
                timeFilterManager.$currentFilter
                    .removeDuplicates(),
                transactionsViewModel.$dataRefreshTrigger  // ✅ NEW: Observe refresh trigger for aggregate rebuild
            ),
            Just(()).eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] combined, _ in
            let (transactionCount, categoryCount, filter, trigger) = combined
            #if DEBUG
            print("🔔 [QuickAddCoordinator] Combine publisher triggered:")
            print("   Transactions: \(transactionCount)")
            print("   Categories: \(categoryCount)")
            print("   Filter: \(filter.displayName)")
            print("   Refresh trigger: \(trigger)")
            #endif
            self?.updateCategories()
        }
        .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Update categories with current data
    func updateCategories() {
        PerformanceProfiler.start("QuickAddCoordinator.updateCategories")

        #if DEBUG
        print("🔄 [QuickAddCoordinator] updateCategories() called")
        print("   Current filter: \(timeFilterManager.currentFilter.displayName)")
        print("   Call stack:")
        Thread.callStackSymbols.prefix(5).forEach { print("   \($0)") }
        #endif

        // Get category expenses from TransactionsViewModel
        let categoryExpenses = transactionsViewModel.categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )

        #if DEBUG
        print("🗂️ [QuickAddCoordinator] Received \(categoryExpenses.count) category expenses from ViewModel")
        if let firstExpense = categoryExpenses.first {
            print("   Example: \(firstExpense.key) = \(String(format: "%.2f", firstExpense.value.total))")
        }
        #endif

        // Map to display data
        let newCategories = categoryMapper.mapCategories(
            customCategories: categoriesViewModel.customCategories,
            categoryExpenses: categoryExpenses,
            type: .expense,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency
        )

        #if DEBUG
        print("🎨 [QuickAddCoordinator] Mapped to \(newCategories.count) display categories")
        if let firstCategory = newCategories.first {
            print("   Example: \(firstCategory.name) = \(String(format: "%.2f", firstCategory.total))")
        }
        #endif

        // ✅ CRITICAL: Assign to @Published property to trigger SwiftUI update
        // Even though categories is @Published, we need to ensure SwiftUI sees the change
        categories = newCategories

        #if DEBUG
        print("✅ [QuickAddCoordinator] Categories published to UI (\(categories.count) items)")
        #endif

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

    /// Update time filter manager (needed when using @EnvironmentObject)
    func setTimeFilterManager(_ manager: TimeFilterManager) {
        guard timeFilterManager !== manager else { return }

        #if DEBUG
        print("🔄 [QuickAddCoordinator] Updating timeFilterManager reference")
        #endif

        timeFilterManager = manager

        // Re-setup bindings with new manager
        cancellables.removeAll()
        setupBindings()
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
