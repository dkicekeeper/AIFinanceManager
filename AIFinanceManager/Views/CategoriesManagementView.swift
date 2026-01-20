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
                // Update transactions to use "Uncategorized" if needed
                categoriesViewModel.deleteCategory(category, deleteTransactions: false)
                transactionsViewModel.invalidateCaches()
                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteCategoryAndTransactions"), role: .destructive) {
                HapticManager.warning()
                // Delete transactions with this category
                transactionsViewModel.allTransactions.removeAll {
                    $0.category == category.name && $0.type == category.type
                }
                transactionsViewModel.recalculateAccountBalances()
                categoriesViewModel.deleteCategory(category, deleteTransactions: true)
                transactionsViewModel.invalidateCaches()
                categoryToDelete = nil
            }
        } message: { category in
            Text(String(format: String(localized: "category.deleteMessage"), category.name))
        }
    }
}

struct CategoryEditView: View {
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    let category: CustomCategory?
    let type: TransactionType
    let onSave: (CustomCategory) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var iconName: String = "banknote.fill"
    @State private var selectedColor: String = "#3b82f6"
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    @State private var showingSubcategoryPicker = false
    @FocusState private var isNameFocused: Bool
    
    // Budget fields (only for expense categories)
    @State private var budgetAmount: String = ""
    @State private var selectedPeriod: CustomCategory.BudgetPeriod = .monthly
    @State private var resetDay: Int = 1
    
    private let defaultColors: [String] = [
        "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
        "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
        "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
    ]
    
    private let commonIcons: [String] = [
        "banknote.fill", "fork.knife", "car.fill", "bag.fill", "sparkles", "lightbulb.fill", "cross.case.fill", "graduationcap.fill",
        "dollarsign.circle.fill", "briefcase.fill", "box.fill", "gift.fill", "airplane", "cart.fill", "cup.and.saucer.fill", "tv.fill",
        "house.fill", "car.fill", "fork.knife", "film.fill", "iphone", "laptopcomputer", "gamecontroller.fill", "dumbbell.fill"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(String(localized: "common.name"))) {
                    TextField(String(localized: "category.namePlaceholder"), text: $name)
                        .focused($isNameFocused)
                }
                
                Section(header: Text(String(localized: "common.icon"))) {
                    HStack {
                        Button(action: { 
                            HapticManager.light()
                            showingIconPicker.toggle() 
                        }) {
                            Image(systemName: iconName)
                                .font(.system(size: AppIconSize.xxl))
                                .foregroundColor(colorFromHex(selectedColor))
                                .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                                .background(Color(.systemGray6))
                                .cornerRadius(AppRadius.lg)
                        }
                        
                        Text(String(localized: "category.tapToSelect"))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text(String(localized: "common.color"))) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.lg) {
                            ForEach(defaultColors, id: \.self) { colorHex in
                                Button(action: { 
                                    HapticManager.selection()
                                    selectedColor = colorHex 
                                }) {
                                    Circle()
                                        .fill(colorFromHex(colorHex))
                                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColor == colorHex ? 3 : 0)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, AppSpacing.sm)
                    }
                }
                
                // Budget section (only for expense categories)
                if type == .expense {
                    Section {
                        TextField(String(localized: "budget_amount"), text: $budgetAmount)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(String(localized: "budget_amount"))
                        
                        Picker(String(localized: "budget_period"), selection: $selectedPeriod) {
                            Text(String(localized: "weekly")).tag(CustomCategory.BudgetPeriod.weekly)
                            Text(String(localized: "monthly")).tag(CustomCategory.BudgetPeriod.monthly)
                            Text(String(localized: "yearly")).tag(CustomCategory.BudgetPeriod.yearly)
                        }
                        .accessibilityLabel(String(localized: "budget_period"))
                        
                        if selectedPeriod == .monthly {
                            Stepper(
                                String(localized: "budget_reset_day") + " \(resetDay)",
                                value: $resetDay,
                                in: 1...31
                            )
                            .accessibilityLabel(String(localized: "budget_reset_day"))
                            .accessibilityValue("\(resetDay)")
                        }
                    } header: {
                        Text(String(localized: "budget_settings"))
                    } footer: {
                        if selectedPeriod == .monthly {
                            Text(String(localized: "budget_reset_day_description"))
                                .font(.caption)
                        }
                    }
                }
                
                // Подкатегории
                if let category = category {
                    Section(header: Text(String(localized: "category.subcategories"))) {
                        let categoryId = category.id
                        let linkedSubcategories = categoriesViewModel.getSubcategoriesForCategory(categoryId)
                        
                        ForEach(linkedSubcategories) { subcategory in
                            HStack {
                                Text(subcategory.name)
                                Spacer()
                                Button(action: {
                                    HapticManager.light()
                                    categoriesViewModel.unlinkSubcategoryFromCategory(subcategoryId: subcategory.id, categoryId: categoryId)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Button(action: { 
                            HapticManager.light()
                            showingSubcategoryPicker = true 
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text(String(localized: "category.addSubcategory"))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSubcategoryPicker) {
                SubcategorySearchView(
                    categoriesViewModel: categoriesViewModel,
                    categoryId: category?.id ?? "",
                    selectedSubcategoryIds: .constant([]),
                    searchText: .constant(""),
                    selectionMode: .single,
                    onSingleSelect: { subcategoryId in
                        if let categoryId = category?.id {
                            categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategoryId, categoryId: categoryId)
                        }
                        showingSubcategoryPicker = false
                    }
                )
            }
            .navigationTitle(category == nil ? String(localized: "modal.newCategory") : String(localized: "modal.editCategory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.light()
                        let budget: Double? = {
                            if type == .expense, !budgetAmount.isEmpty, let amount = Double(budgetAmount), amount > 0 {
                                return amount
                            }
                            return nil
                        }()
                        
                        let newCategory = CustomCategory(
                            id: category?.id ?? UUID().uuidString,
                            name: name,
                            iconName: iconName,
                            colorHex: selectedColor,
                            type: type,
                            budgetAmount: budget,
                            budgetPeriod: selectedPeriod,
                            budgetResetDay: resetDay
                        )
                        onSave(newCategory)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.isEmpty || iconName.isEmpty)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIconName: $iconName)
            }
            .onAppear {
                if let category = category {
                    name = category.name
                    iconName = category.iconName
                    selectedColor = category.colorHex
                    isNameFocused = false
                    
                    // Load budget fields if exists
                    if let amount = category.budgetAmount {
                        budgetAmount = String(Int(amount))
                    } else {
                        budgetAmount = ""
                    }
                    selectedPeriod = category.budgetPeriod
                    resetDay = category.budgetResetDay
                } else {
                    // Активируем поле названия при создании новой категории
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                        isNameFocused = true
                    }
                }
            }
        }
    }
    
    // Используем метод из CustomCategory для конвертации hex в Color
    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
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

#Preview("Category Edit View - New") {
    let coordinator = AppCoordinator()
    
    return CategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        category: nil,
        type: .expense,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Category Edit View - Edit") {
    let coordinator = AppCoordinator()
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
    
    return CategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        category: sampleCategory,
        type: .expense,
        onSave: { _ in },
        onCancel: {}
    )
}
