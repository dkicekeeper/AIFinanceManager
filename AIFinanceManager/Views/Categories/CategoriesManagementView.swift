//
//  CategoriesManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CategoriesManagementView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: TransactionType = .expense
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var categoryToDelete: CustomCategory?
    @State private var showingDeleteDialog = false
    
    // Кешируем отфильтрованные категории для оптимизации
    private var filteredCategories: [CustomCategory] {
        let filtered = categoriesViewModel.customCategories
            .filter { $0.type == selectedType }

        // Sort by custom order if available, otherwise by name
        return filtered.sorted { cat1, cat2 in
            // If both have order, sort by order
            if let order1 = cat1.order, let order2 = cat2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if cat1.order != nil {
                return true
            }
            if cat2.order != nil {
                return false
            }
            // If neither has order, sort by name
            return cat1.name < cat2.name
        }
    }

    // MARK: - Methods

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var updatedCategories = filteredCategories
        updatedCategories.move(fromOffsets: source, toOffset: destination)

        // Update order for all categories of this type
        for (index, category) in updatedCategories.enumerated() {
            var updatedCategory = category
            updatedCategory.order = index
            categoriesViewModel.updateCategory(updatedCategory)
        }

        // Invalidate caches to ensure the new order is reflected everywhere
        transactionsViewModel.invalidateCaches()

        HapticManager.selection()
    }

    var body: some View {
        Group {
            if filteredCategories.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: String(localized: "emptyState.noCategories"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "button.add"),
                    action: {
                        showingAddCategory = true
                    }
                )
            } else {
                List {
                    ForEach(filteredCategories) { category in
                        CategoryRow(
                            category: category,
                            isDefault: false,
                            budgetProgress: category.type == .expense ? categoriesViewModel.budgetProgress(for: category, transactions: transactionsViewModel.allTransactions) : nil,
                            onEdit: { editingCategory = category },
                            onDelete: {
                                categoryToDelete = category
                                showingDeleteDialog = true
                            }
                        )
                    }
                    .onMove(perform: moveCategory)
                }
                .environment(\.editMode, .constant(.active))
            }
        }
        .navigationTitle(String(localized: "navigation.categories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    showingAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("", selection: $selectedType) {
                Text(String(localized: "transactionType.expense")).tag(TransactionType.expense)
                Text(String(localized: "transactionType.income")).tag(TransactionType.income)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(Color(.clear))
            .onChange(of: selectedType) { _, _ in
                HapticManager.selection()
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: nil,
                type: selectedType,
                onSave: { category in
                    HapticManager.success()
                    categoriesViewModel.addCategory(category)
                    transactionsViewModel.invalidateCaches()
                    showingAddCategory = false
                },
                onCancel: { showingAddCategory = false }
            )
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: category,
                type: category.type,
                onSave: { updatedCategory in
                    HapticManager.success()
                    categoriesViewModel.updateCategory(updatedCategory)
                    transactionsViewModel.invalidateCaches()
                    editingCategory = nil
                },
                onCancel: { editingCategory = nil }
            )
        }
        .alert(String(localized: "category.deleteTitle"), isPresented: $showingDeleteDialog, presenting: categoryToDelete) { category in
            Button(String(localized: "button.cancel"), role: .cancel) {
                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteOnlyCategory"), role: .destructive) {
                HapticManager.warning()

                // Delete category (transactions keep the category name as string)
                categoriesViewModel.deleteCategory(category, deleteTransactions: false)

                // ✅ CATEGORY REFACTORING: No manual sync needed!
                // customCategories automatically synced via Combine publisher

                // Phase 8: saveToStorage removed - persistence automatic via TransactionStore
                // Phase 8: Cache rebuild removed - automatic via TransactionStore

                // CRITICAL: Clear and rebuild aggregate cache to remove deleted category entity
                // Even though transactions remain, we need to rebuild so the category disappears from UI
                transactionsViewModel.clearAndRebuildAggregateCache()

                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteCategoryAndTransactions"), role: .destructive) {
                HapticManager.warning()

                // Delete transactions with this category
                let txnsToDelete = transactionsViewModel.allTransactions.filter {
                    $0.category == category.name && $0.type == category.type
                }

                transactionsViewModel.allTransactions.removeAll {
                    $0.category == category.name && $0.type == category.type
                }

                // CRITICAL FIX: Invalidate ALL caches IMMEDIATELY after transaction deletion
                // This prevents summary() from returning stale cached data
                transactionsViewModel.invalidateCaches()

                transactionsViewModel.recalculateAccountBalances()

                // Delete category
                categoriesViewModel.deleteCategory(category, deleteTransactions: true)

                // ✅ CATEGORY REFACTORING: No manual sync needed!
                // customCategories automatically synced via Combine publisher

                // Phase 8: saveToStorage removed - persistence automatic via TransactionStore
                // Phase 8: Cache rebuild removed - automatic via TransactionStore

                // CRITICAL: Clear and rebuild aggregate cache since transactions deleted
                transactionsViewModel.clearAndRebuildAggregateCache()

                categoryToDelete = nil
            }
        } message: { category in
            Text(String(format: String(localized: "category.deleteMessage"), category.name))
        }
    }
}

// MARK: - Previews

#Preview("Categories Management") {
    let coordinator = AppCoordinator()
    NavigationView {
        CategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Categories Management - Empty") {
    let coordinator = AppCoordinator()
    // ✅ CATEGORY REFACTORING: Use updateCategories for controlled mutation
    coordinator.categoriesViewModel.updateCategories([])

    return NavigationView {
        CategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Category Row") {
    let sampleCategory = CustomCategory(
        id: "preview",
        name: "Food",
        iconName: "fork.knife",
        colorHex: "#3b82f6",
        type: .expense,
        budgetAmount: 10000,
        budgetPeriod: .monthly,
        budgetResetDay: 1
    )

    return List {
        CategoryRow(
            category: sampleCategory,
            isDefault: false,
            budgetProgress: nil,
            onEdit: {},
            onDelete: {}
        )
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
