//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct QuickAddTransactionView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var selectedCategory: String? = nil
    @State private var selectedType: TransactionType = .expense
    @State private var showingAddCategory = false

    // Кешированные данные для производительности
    @State private var cachedCategories: [String] = []
    @State private var cachedCategoryExpenses: [String: CategoryExpense] = [:]
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        let categories = cachedCategories
        let categoryExpenses = cachedCategoryExpenses
        
        Group {
            if categories.isEmpty {
                Button(action: {
                    HapticManager.light()
                    showingAddCategory = true
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(String(localized: "categories.expenseCategories", defaultValue: "Категории расходов"))
                                .font(AppTypography.h3)
                                .foregroundStyle(.primary)
                        }
                        
                        EmptyStateView(title: String(localized: "emptyState.noCategories", defaultValue: "Нет категорий"), style: .compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardStyle(radius: AppRadius.pill)
                }
                .buttonStyle(.bounce)
            } else {
                LazyVGrid(columns: gridColumns, spacing: AppSpacing.lg) {
                    ForEach(categories, id: \.self) { category in
                        let total = categoryExpenses[category]?.total ?? 0
                        let currency = transactionsViewModel.appSettings.baseCurrency
                        let totalText = total != 0 ? Formatting.formatCurrency(total, currency: currency) : nil
                        
                        // Get custom category for budget info
                        let customCategory = categoriesViewModel.customCategories.first { 
                            $0.name.lowercased() == category.lowercased() && $0.type == .expense 
                        }
                        
                        // Calculate budget progress
                        let budgetProgress: BudgetProgress? = {
                            if let customCategory = customCategory {
                                return categoriesViewModel.budgetProgress(
                                    for: customCategory,
                                    transactions: transactionsViewModel.allTransactions
                                )
                            }
                            return nil
                        }()

                        VStack(spacing: AppSpacing.xs) {
                            CategoryChip(
                                category: category,
                                type: .expense,
                                customCategories: categoriesViewModel.customCategories,
                                isSelected: false,
                                onTap: {
                                    selectedCategory = category
                                    selectedType = .expense
                                },
                                budgetProgress: budgetProgress,
                                budgetAmount: customCategory?.budgetAmount
                            )
                            
                            if let totalText = totalText {
                                Text(totalText)
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Show budget amount if exists
                            if let budgetAmount = customCategory?.budgetAmount {
                                Text(Formatting.formatCurrency(budgetAmount, currency: currency))
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
        }
        .overlay(Color.white.opacity(0.001).allowsHitTesting(false))
        .sheet(isPresented: Binding(
            get: { selectedCategory != nil },
            set: { if !$0 { selectedCategory = nil } }
        )) {
            if let category = selectedCategory {
                AddTransactionModal(
                    category: category,
                    type: selectedType,
                    currency: transactionsViewModel.appSettings.baseCurrency,
                    accounts: accountsViewModel.accounts,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    onDismiss: {
                        selectedCategory = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: nil,
                type: .expense,
                onSave: { category in
                    HapticManager.success()
                    categoriesViewModel.addCategory(category)
                    transactionsViewModel.invalidateCaches()
                    showingAddCategory = false
                },
                onCancel: { showingAddCategory = false }
            )
        }
        .onAppear {
            updateCachedData()
        }
        .onChange(of: transactionsViewModel.allTransactions.count) { _, _ in
            updateCachedData()
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            updateCachedData()
        }
        .onChange(of: categoriesViewModel.customCategories.count) { _, _ in
            updateCachedData()
        }
    }

    // Обновление кешированных данных с debouncing
    private func updateCachedData() {
        // Отменить предыдущую задачу обновления
        updateTask?.cancel()

        // Запустить новую задачу с debouncing
        updateTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms debounce
            guard !Task.isCancelled else { return }

            await MainActor.run {
                PerformanceProfiler.start("QuickAddTransactionView.updateCachedData")
                cachedCategoryExpenses = transactionsViewModel.categoryExpenses(
                    timeFilterManager: timeFilterManager,
                    categoriesViewModel: categoriesViewModel
                )
                cachedCategories = popularCategories()
                PerformanceProfiler.end("QuickAddTransactionView.updateCachedData")
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }

    private func popularCategories() -> [String] {
        // Получаем все категории: только пользовательские + из транзакций
        var allCategories = Set<String>()

        // Создаем Set существующих категорий для быстрой проверки
        let existingCategoryNames = Set(categoriesViewModel.customCategories.map { $0.name })

        print("📋 [popularCategories] customCategories count: \(categoriesViewModel.customCategories.count)")
        print("📋 [popularCategories] existingCategoryNames: \(existingCategoryNames)")

        // Добавляем пользовательские категории расходов
        for customCategory in categoriesViewModel.customCategories where customCategory.type == .expense {
            allCategories.insert(customCategory.name)
        }

        print("📋 [popularCategories] allCategories after adding custom: \(allCategories)")

        // CRITICAL FIX: Добавляем категории из транзакций ТОЛЬКО если они существуют в customCategories
        // Это предотвращает отображение удалённых категорий, даже если транзакции с ними остались
        let popularFromTransactions = transactionsViewModel.popularCategories(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )
        for category in popularFromTransactions {
            // Проверяем что категория существует в customCategories
            if existingCategoryNames.contains(category) {
                allCategories.insert(category)
            }
        }

        // Сортируем по популярности (сумме расходов с учетом фильтра)
        let categoryExpenses = transactionsViewModel.categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )
        return Array(allCategories).sorted { category1, category2 in
            let total1 = categoryExpenses[category1]?.total ?? 0
            let total2 = categoryExpenses[category2]?.total ?? 0
            if total1 != total2 {
                return total1 > total2
            }
            return category1 < category2
        }
    }
}


struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(String(localized: "quickAdd.selectDate"), selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()

                Spacer()
            }
            .navigationTitle(String(localized: "quickAdd.selectDate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "quickAdd.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "quickAdd.done")) {
                        onDateSelected(selectedDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
#Preview {
    let coordinator = AppCoordinator()
    QuickAddTransactionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel
    )
        .environmentObject(TimeFilterManager())
}
