//
//  CategoryEditView.swift
//  AIFinanceManager
//
//  Migrated to hero-style UI (Phase 16 - 2026-02-16)
//  Uses EditableHeroSection with color picker and beautiful animations
//

import SwiftUI

struct CategoryEditView: View {
    let categoriesViewModel: CategoriesViewModel
    let transactionsViewModel: TransactionsViewModel
    let category: CustomCategory?
    let type: TransactionType
    let onSave: (CustomCategory) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedIconSource: IconSource? = .sfSymbol("banknote.fill")
    @State private var selectedColor: String = "#3b82f6"
    @State private var showingSubcategoryPicker = false
    @State private var validationError: String? = nil

    // Budget fields (only for expense categories)
    @State private var budgetAmount: String = ""
    @State private var selectedPeriod: CustomCategory.BudgetPeriod = .monthly
    @State private var resetDay: Int = 1

    private var parsedBudget: Double? {
        guard type == .expense, !budgetAmount.isEmpty, let amount = Double(budgetAmount), amount > 0 else {
            return nil
        }
        return amount
    }

    var body: some View {
        EditSheetContainer(
            title: category == nil ? String(localized: "modal.newCategory") : String(localized: "modal.editCategory"),
            isSaveDisabled: name.isEmpty,
            onSave: saveCategory,
            onCancel: onCancel
        ) {
            VStack(spacing: 0) {
                // Hero Section with Icon, Name, and Color Picker
                EditableHeroSection(
                    iconSource: $selectedIconSource,
                    title: $name,
                    selectedColor: $selectedColor,
                    titlePlaceholder: String(localized: "category.namePlaceholder"),
                    config: .categoryHero
                )
                .padding(.horizontal, AppSpacing.lg)

                // Validation Error
                if let error = validationError {
                    MessageBanner.error(error)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Budget Settings Section (expense categories only)
                if type == .expense {
                    Section {
                        VStack(spacing: 0) {
                            // Budget Amount
                            HStack {
                                Text(String(localized: "budget.amount"))
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                TextField("0", text: $budgetAmount)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityLabel(String(localized: "budget.amount"))
                            }
                            .padding(AppSpacing.md)

                            Divider()

                            // Budget Period
                            Picker(String(localized: "budget.period"), selection: $selectedPeriod) {
                                Text(String(localized: "budget.weekly")).tag(CustomCategory.BudgetPeriod.weekly)
                                Text(String(localized: "budget.monthly")).tag(CustomCategory.BudgetPeriod.monthly)
                                Text(String(localized: "yearly")).tag(CustomCategory.BudgetPeriod.yearly)
                            }
                            .padding(AppSpacing.md)
                            .accessibilityLabel(String(localized: "budget.period"))

                            if selectedPeriod == .monthly {
                                Divider()

                                // Reset Day
                                Stepper(
                                    String(localized: "budget_reset_day") + " \(resetDay)",
                                    value: $resetDay,
                                    in: 1...31
                                )
                                .padding(AppSpacing.md)
                                .accessibilityLabel(String(localized: "budget_reset_day"))
                                .accessibilityValue("\(resetDay)")
                            }
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

                // Subcategories Section (edit mode only)
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
                                        .foregroundStyle(.red)
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
                            .foregroundStyle(.blue)
                        }
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let category = category {
                name = category.name
                selectedIconSource = category.iconSource
                selectedColor = category.colorHex

                // Load budget fields if exists
                if let amount = category.budgetAmount {
                    budgetAmount = String(Int(amount))
                } else {
                    budgetAmount = ""
                }
                selectedPeriod = category.budgetPeriod
                resetDay = category.budgetResetDay
            }
        }
    }

    // MARK: - Save Category

    private func saveCategory() {
        // Validate name
        guard !name.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.categoryNameRequired")
            }
            HapticManager.error()
            return
        }

        // Clear validation error
        validationError = nil

        let newCategory = CustomCategory(
            id: category?.id ?? UUID().uuidString,
            name: name,
            iconSource: selectedIconSource ?? .sfSymbol("star.fill"),
            colorHex: selectedColor,
            type: type,
            budgetAmount: parsedBudget,
            budgetPeriod: selectedPeriod,
            budgetResetDay: resetDay
        )

        HapticManager.success()
        onSave(newCategory)
    }
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
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#ec4899",
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
