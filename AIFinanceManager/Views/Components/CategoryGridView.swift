//
//  CategoryGridView.swift
//  AIFinanceManager
//
//  Reusable category grid component with adaptive columns.
//  Displays categories with totals and budget information.
//

import SwiftUI

struct CategoryGridView: View {
    let categories: [CategoryDisplayData]
    let baseCurrency: String
    let gridColumns: Int?
    let onCategoryTap: (String, TransactionType) -> Void
    let emptyStateAction: (() -> Void)?

    // MARK: - Body

    var body: some View {
        Group {
            if categories.isEmpty {
                emptyState
            } else {
                categoryGrid
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if let action = emptyStateAction {
                Button(action: {
                    HapticManager.light()
                    action()
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(String(localized: "categories.expenseCategories", defaultValue: "Expense Categories"))
                                .font(AppTypography.h3)
                                .foregroundStyle(.primary)
                        }

                        EmptyStateView(
                            title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                            style: .compact
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardStyle(radius: AppRadius.pill)
                }
                .buttonStyle(.bounce)
            } else {
                EmptyStateView(
                    title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                    style: .compact
                )
            }
        }
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: AppSpacing.lg) {
            ForEach(categories) { category in
                CategoryGridItem(
                    category: category,
                    baseCurrency: baseCurrency,
                    onTap: {
                        onCategoryTap(category.name, category.type)
                    }
                )
            }
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Adaptive Columns

    private var adaptiveColumns: [GridItem] {
        if let columns = gridColumns {
            return Array(
                repeating: GridItem(.flexible(), spacing: AppSpacing.md),
                count: columns
            )
        }

        // Adaptive based on screen width
        let screenWidth = UIScreen.main.bounds.width
        let minColumnWidth: CGFloat = 80
        let spacing: CGFloat = AppSpacing.md
        let horizontalPadding: CGFloat = AppSpacing.lg * 2

        let availableWidth = screenWidth - horizontalPadding
        let columns = Int((availableWidth + spacing) / (minColumnWidth + spacing))
        let clampedColumns = min(max(columns, 3), 6) // 3-6 columns

        return Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: clampedColumns
        )
    }
}

// MARK: - Category Grid Item

private struct CategoryGridItem: View {
    let category: CategoryDisplayData
    let baseCurrency: String
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            CategoryChip(
                category: category.name,
                type: category.type,
                customCategories: [], // Style info already in CategoryDisplayData
                isSelected: false,
                onTap: onTap,
                budgetProgress: category.budgetProgress,
                budgetAmount: category.budgetAmount
            )

            if let totalText = category.formattedTotal(currency: baseCurrency) {
                Text(totalText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let budgetText = category.formattedBudget(currency: baseCurrency) {
                Text(budgetText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview

#Preview("Category Grid - With Data") {
    CategoryGridView(
        categories: [
            CategoryDisplayData(
                id: "1",
                name: "Food",
                type: .expense,
                iconName: "fork.knife",
                iconColor: .orange,
                total: 5000,
                budgetAmount: 10000,
                budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 5000)
            ),
            CategoryDisplayData(
                id: "2",
                name: "Transport",
                type: .expense,
                iconName: "car.fill",
                iconColor: .blue,
                total: 3000,
                budgetAmount: 5000,
                budgetProgress: BudgetProgress(budgetAmount: 5000, spent: 3000)
            )
        ],
        baseCurrency: "USD",
        gridColumns: nil,
        onCategoryTap: { _, _ in },
        emptyStateAction: nil
    )
}

#Preview("Category Grid - Empty") {
    CategoryGridView(
        categories: [],
        baseCurrency: "USD",
        gridColumns: 4,
        onCategoryTap: { _, _ in },
        emptyStateAction: { print("Add category") }
    )
}
