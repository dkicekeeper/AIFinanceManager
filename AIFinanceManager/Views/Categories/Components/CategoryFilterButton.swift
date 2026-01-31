//
//  CategoryFilterButton.swift
//  AIFinanceManager
//
//  Reusable category filter button component
//

import SwiftUI

struct CategoryFilterButton: View {
    let selectedCategories: Set<String>?
    let customCategories: [CustomCategory]
    let incomeCategories: [String]
    let onTap: () -> Void

    private var categoryFilterText: String {
        guard let selectedCategories = selectedCategories else {
            return "Все категории"
        }
        if selectedCategories.count == 1 {
            return selectedCategories.first ?? "Все категории"
        }
        return "\(selectedCategories.count) категорий"
    }

    @ViewBuilder
    private var categoryFilterIcon: some View {
        if let selectedCategories = selectedCategories,
           selectedCategories.count == 1,
           let category = selectedCategories.first {
            let isIncome: Bool = {
                if let customCategory = customCategories.first(where: { $0.name == category }) {
                    return customCategory.type == .income
                } else {
                    return incomeCategories.contains(category)
                }
            }()
            let categoryType: TransactionType = isIncome ? .income : .expense
            let iconName = CategoryIcon.iconName(for: category, type: categoryType, customCategories: customCategories)
            let iconColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(isIncome ? Color.green : iconColor)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                categoryFilterIcon
                Text(categoryFilterText)
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle(isSelected: selectedCategories != nil)
        }
    }
}

#Preview {
    CategoryFilterButton(
        selectedCategories: Set(["Food"]),
        customCategories: [],
        incomeCategories: ["Salary"],
        onTap: {}
    )
    .padding()
}
