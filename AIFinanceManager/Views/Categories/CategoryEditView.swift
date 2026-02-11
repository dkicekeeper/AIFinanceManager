//
//  CategoryEditView.swift
//  AIFinanceManager
//
//  Created on 2024
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

    private var parsedBudget: Double? {
        guard type == .expense, !budgetAmount.isEmpty, let amount = Double(budgetAmount), amount > 0 else {
            return nil
        }
        return amount
    }

    var body: some View {
        EditSheetContainer(
            title: category == nil ? String(localized: "modal.newCategory") : String(localized: "modal.editCategory"),
            isSaveDisabled: name.isEmpty || iconName.isEmpty,
            onSave: {
                let newCategory = CustomCategory(
                    id: category?.id ?? UUID().uuidString,
                    name: name,
                    iconName: iconName,
                    colorHex: selectedColor,
                    type: type,
                    budgetAmount: parsedBudget,
                    budgetPeriod: selectedPeriod,
                    budgetResetDay: resetDay
                )
                onSave(newCategory)
            },
            onCancel: onCancel
        ) {
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
                            .foregroundStyle(colorFromHex(selectedColor))
                            .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                            .background(Color(.systemGray6))
                            .clipShape(.rect(cornerRadius: AppRadius.lg))
                    }

                    Text(String(localized: "category.tapToSelect"))
                        .foregroundStyle(.secondary)
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
                    TextField(String(localized: "budget.amount"), text: $budgetAmount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(String(localized: "budget.amount"))

                    Picker(String(localized: "budget.period"), selection: $selectedPeriod) {
                        Text(String(localized: "budget.weekly")).tag(CustomCategory.BudgetPeriod.weekly)
                        Text(String(localized: "budget.monthly")).tag(CustomCategory.BudgetPeriod.monthly)
                        Text(String(localized: "yearly")).tag(CustomCategory.BudgetPeriod.yearly)
                    }
                    .accessibilityLabel(String(localized: "budget.period"))

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
