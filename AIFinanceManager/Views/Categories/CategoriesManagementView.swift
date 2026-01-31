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
        categoriesViewModel.customCategories
            .filter { $0.type == selectedType }
            .sorted { $0.name < $1.name }
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
                }
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
                print("🗑️ [CategoryDeleteOnly] Deleting category '\(category.name)' WITHOUT transactions")

                // Delete category (transactions keep the category name as string)
                categoriesViewModel.deleteCategory(category, deleteTransactions: false)

                // CRITICAL: Clear and rebuild aggregate cache to remove deleted category entity
                // Even though transactions remain, we need to rebuild so the category disappears from UI
                transactionsViewModel.clearAndRebuildAggregateCache()

                print("🗑️ [CategoryDeleteOnly] Completed - transactions keep category name as string")
                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteCategoryAndTransactions"), role: .destructive) {
                HapticManager.warning()
                print("🗑️ [CategoryDelete+Txns] Deleting category '\(category.name)' with transactions")

                // Delete transactions with this category
                let txnsToDelete = transactionsViewModel.allTransactions.filter {
                    $0.category == category.name && $0.type == category.type
                }
                print("🗑️ [CategoryDelete+Txns] Removing \(txnsToDelete.count) transactions")

                transactionsViewModel.allTransactions.removeAll {
                    $0.category == category.name && $0.type == category.type
                }

                // CRITICAL FIX: Invalidate ALL caches IMMEDIATELY after transaction deletion
                // This prevents summary() from returning stale cached data
                transactionsViewModel.invalidateCaches()

                transactionsViewModel.recalculateAccountBalances()

                // Delete category
                categoriesViewModel.deleteCategory(category, deleteTransactions: true)

                // CRITICAL: Save to storage so deletions persist after app restart
                transactionsViewModel.saveToStorageSync()

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
    coordinator.categoriesViewModel.customCategories = []

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
