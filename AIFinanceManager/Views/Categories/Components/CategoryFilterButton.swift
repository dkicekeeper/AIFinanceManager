//
//  CategoryFilterButton.swift
//  AIFinanceManager
//
//  Reusable category filter button component
//

import SwiftUI

struct CategoryFilterButton: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    let onTap: () -> Void
    
    private var categoryFilterText: String {
        guard let selectedCategories = transactionsViewModel.selectedCategories else {
            return "Все категории"
        }
        if selectedCategories.count == 1 {
            return selectedCategories.first ?? "Все категории"
        }
        return "\(selectedCategories.count) категорий"
    }
    
    @ViewBuilder
    private var categoryFilterIcon: some View {
        if let selectedCategories = transactionsViewModel.selectedCategories,
           selectedCategories.count == 1,
           let category = selectedCategories.first {
            let isIncome: Bool = {
                if let customCategory = categoriesViewModel.customCategories.first(where: { $0.name == category }) {
                    return customCategory.type == .income
                } else {
                    return transactionsViewModel.incomeCategories.contains(category)
                }
            }()
            let categoryType: TransactionType = isIncome ? .income : .expense
            let iconName = CategoryIcon.iconName(for: category, type: categoryType, customCategories: categoriesViewModel.customCategories)
            let iconColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: categoriesViewModel.customCategories)
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
            .filterChipStyle(isSelected: transactionsViewModel.selectedCategories != nil)
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    CategoryFilterButton(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        onTap: {}
    )
    .padding()
}
