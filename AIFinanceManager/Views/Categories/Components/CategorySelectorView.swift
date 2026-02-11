//
//  CategorySelectorView.swift
//  AIFinanceManager
//
//  Reusable category selector component with grid layout
//

import SwiftUI

struct CategorySelectorView: View {
    let categories: [String]
    let type: TransactionType
    let customCategories: [CustomCategory]
    @Binding var selectedCategory: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    let budgetProgressMap: [String: BudgetProgress]?
    let budgetAmountMap: [String: Double]?
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4)
    }
    
    init(
        categories: [String],
        type: TransactionType,
        customCategories: [CustomCategory],
        selectedCategory: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil,
        budgetProgressMap: [String: BudgetProgress]? = nil,
        budgetAmountMap: [String: Double]? = nil
    ) {
        self.categories = categories
        self.type = type
        self.customCategories = customCategories
        self._selectedCategory = selectedCategory
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
        self.budgetProgressMap = budgetProgressMap
        self.budgetAmountMap = budgetAmountMap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if categories.isEmpty {
                if let message = emptyStateMessage {
                    Text(message)
                        .font(AppTypography.bodyLarge)
                        .foregroundStyle(.secondary)
                        .padding(AppSpacing.lg)
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
                    ForEach(categories, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            type: type,
                            customCategories: customCategories,
                            isSelected: selectedCategory == category,
                            onTap: {
                                selectedCategory = category
                                onSelectionChange?(category)
                            },
                            budgetProgress: budgetProgressMap?[category],
                            budgetAmount: budgetAmountMap?[category]
                        )
                    }
                }
                .padding(AppSpacing.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .stroke(warningMessage != nil ? Color.orange : Color.clear, lineWidth: 1)
                        .padding(.horizontal, AppSpacing.lg)
                )
            }
            
            if let warning = warningMessage {
                WarningMessageView(message: warning)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedCategory: String? = nil
    
    return VStack {
        CategorySelectorView(
            categories: ["Food", "Transport", "Shopping", "Entertainment"],
            type: .expense,
            customCategories: [],
            selectedCategory: $selectedCategory,
            emptyStateMessage: nil,
            warningMessage: nil
        )
        
        CategorySelectorView(
            categories: [],
            type: .expense,
            customCategories: [],
            selectedCategory: $selectedCategory,
            emptyStateMessage: "No categories available",
            warningMessage: nil
        )
    }
    .padding()
}
