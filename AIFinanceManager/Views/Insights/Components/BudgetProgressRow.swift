//
//  BudgetProgressRow.swift
//  AIFinanceManager
//
//  Full budget progress row: icon + name + BudgetProgressBar + spent/budget amounts.
//  Extracted from InsightDetailView.budgetChartSection — Phase 26.
//

import SwiftUI

/// One row in the budget breakdown list.
/// Shows category name, progress bar, spent vs budget amounts, and remaining days.
struct BudgetProgressRow: View {
    let item: BudgetInsightItem
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Icon + name + percentage
            HStack {
                if let iconSource = item.iconSource {
                    IconView(source: iconSource, size: AppIconSize.lg)
                }
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", item.percentage))
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.isOverBudget ? AppColors.destructive : AppColors.textPrimary)
            }

            // Progress bar
            BudgetProgressBar(
                percentage: item.percentage,
                isOverBudget: item.isOverBudget,
                color: item.color
            )

            // Spent / Budget / Days left
            HStack {
                FormattedAmountText(
                    amount: item.spent,
                    currency: currency,
                    fontSize: AppTypography.caption,
                    fontWeight: .regular,
                    color: AppColors.textSecondary
                )
                Text("/")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                FormattedAmountText(
                    amount: item.budgetAmount,
                    currency: currency,
                    fontSize: AppTypography.caption,
                    fontWeight: .regular,
                    color: AppColors.textSecondary
                )
                Spacer()
                if item.daysRemaining > 0 {
                    Text(String(format: String(localized: "insights.daysLeft"), item.daysRemaining))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}
