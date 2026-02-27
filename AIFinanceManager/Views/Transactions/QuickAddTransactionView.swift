//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Quick add transaction view with category grid.
//  Refactored to follow Props + Callbacks pattern with zero ViewModel dependencies.
//

import SwiftUI

// MARK: - Category Selection Model

/// Helper struct to make category selection Identifiable for .sheet(item:)
private struct CategorySelection: Identifiable {
    let id = UUID()
    let category: String
    let type: TransactionType
}

// MARK: - QuickAddTransactionView

struct QuickAddTransactionView: View {

    // MARK: - Coordinator

    @State private var coordinator: QuickAddCoordinator

    // MARK: - Environment

    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - Performance Optimization State

    /// ✅ OPTIMIZATION: Debounce task to prevent rapid consecutive updates
    @State private var debounceTask: Task<Void, Never>?

    /// ✅ OPTIMIZATION: Track last refresh trigger value to skip redundant updates
    @State private var lastRefreshTrigger: Int = 0

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        // Fix #4: accept the real TimeFilterManager so QuickAddCoordinator computes
        // categories with the correct filter on the very first body evaluation.
        // Previously a dummy TimeFilterManager() was used and replaced in onAppear,
        // causing two category-computation passes with different filter values.
        timeFilterManager: TimeFilterManager
    ) {
        _coordinator = State(initialValue: QuickAddCoordinator(
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore,
            timeFilterManager: timeFilterManager
        ))
    }

    // MARK: - Body

    var body: some View {
        CategoryGridView(
            categories: coordinator.categories,
            baseCurrency: coordinator.baseCurrency,
            gridColumns: nil, // Adaptive
            onCategoryTap: { category, type in
                coordinator.handleCategorySelected(category, type: type)
            },
            emptyStateAction: coordinator.handleAddCategory
        )
        // ✅ OPTIMIZATION: Removed .id(categoriesHash) - @Observable automatically tracks changes
        // ✅ PERFORMANCE FIX: Use .sheet(item:) instead of custom Binding
        // This is much faster - SwiftUI optimizes item-based sheets
        .sheet(item: Binding(
            get: {
                // Convert String? to CategorySelection?
                coordinator.selectedCategory.map { CategorySelection(category: $0, type: coordinator.selectedType) }
            },
            set: { newValue in
                // Dismiss if nil
                if newValue == nil {
                    coordinator.dismissModal()
                }
            }
        )) { selection in
            addTransactionSheet(for: selection.category, type: selection.type)
        }
        .sheet(isPresented: $coordinator.showingAddCategory) {
            categoryEditSheet
        }
        // ✅ OPTIMIZATION: Single debounced trigger instead of three separate onChange handlers
        // This prevents cascading updates during CSV imports and data loading
        .onChange(of: refreshTrigger) { old, new in
            // ✅ OPTIMIZATION: Skip if value didn't actually change (deduplication)
            guard old != new else { return }

            // ✅ OPTIMIZATION: Skip if same as last processed value
            guard new != lastRefreshTrigger else { return }

            // Cancel previous debounce task
            debounceTask?.cancel()

            // Create new debounced task
            debounceTask = Task {
                // Wait 150ms to batch multiple rapid changes
                try? await Task.sleep(for: .milliseconds(150))

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                // Perform update on main actor
                await MainActor.run {
                    lastRefreshTrigger = new
                    coordinator.refreshData()
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// ✅ OPTIMIZATION: Combined refresh trigger that watches all data sources
    /// Prevents multiple .onChange handlers and enables debouncing
    ///
    /// Uses XOR of:
    ///  - current time filter (changes when user switches filter)
    ///  - category count (changes when category is added/removed)
    ///  - transaction count (changes when a transaction is added/deleted)
    ///  - category style hash (changes when icon or color is edited — O(N) over categories, N≈10-20)
    ///
    /// NOTE: expenseAmountHash (O(N) filter+reduce over all transactions) was removed.
    /// Amount-only edits won't refresh the grid, but count/filter changes cover the
    /// common cases and avoid blocking the main thread on every body evaluation.
    private var refreshTrigger: Int {
        let categories = coordinator.categoriesViewModel.customCategories
        let budgetedCount = categories.filter { $0.budgetAmount != nil }.count
        let categoryStyleHash = categories.reduce(0) { acc, cat in
            acc ^ cat.iconSource.hashValue ^ cat.colorHex.hashValue
        }
        return timeFilterManager.currentFilter.hashValue
            ^ categories.count
            ^ coordinator.transactionsViewModel.allTransactions.count
            ^ budgetedCount
            ^ categoryStyleHash
    }

    // MARK: - Sheets

    private func addTransactionSheet(for category: String, type: TransactionType) -> some View {
        AddTransactionModal(
            category: category,
            type: type,
            currency: coordinator.baseCurrency,
            accounts: coordinator.accounts,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionStore: coordinator.transactionStore,
            onDismiss: coordinator.dismissModal
        )
        .environment(timeFilterManager)
    }

    private var categoryEditSheet: some View {
        CategoryEditView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            category: nil,
            type: .expense,
            onSave: coordinator.handleCategoryAdded,
            onCancel: { coordinator.showingAddCategory = false }
        )
    }
}

// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    let tfm = TimeFilterManager()
    QuickAddTransactionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore,
        timeFilterManager: tfm
    )
    .environment(tfm)
}
