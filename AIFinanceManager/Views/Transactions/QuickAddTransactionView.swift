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

    @StateObject private var coordinator: QuickAddCoordinator

    // MARK: - Environment

    @EnvironmentObject var timeFilterManager: TimeFilterManager

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore
    ) {
        _coordinator = StateObject(wrappedValue: QuickAddCoordinator(
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: transactionStore,
            timeFilterManager: TimeFilterManager() // Will be replaced by @EnvironmentObject
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
        .id(categoriesHash)  // ✅ Force SwiftUI to redraw when categories change
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
        .onAppear {
            // ✅ FIX: Update coordinator's timeFilterManager to use @EnvironmentObject
            coordinator.setTimeFilterManager(timeFilterManager)
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            // ✅ FIX: Ensure coordinator uses correct filter when it changes
            coordinator.updateCategories()
        }
    }

    // Compute hash of all category totals AND order to detect changes
    private var categoriesHash: Int {
        coordinator.categories.enumerated().reduce(0) { hash, element in
            let (index, category) = element
            // Include index to detect reordering, name for identity, and total for value changes
            return hash ^ index.hashValue ^ category.name.hashValue ^ category.total.hashValue
        }
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
        .environmentObject(timeFilterManager)
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
    QuickAddTransactionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactionStore: coordinator.transactionStore
    )
    .environmentObject(TimeFilterManager())
}
