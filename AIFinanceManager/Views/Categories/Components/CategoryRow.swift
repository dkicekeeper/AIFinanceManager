//
//  CategoryRow.swift
//  AIFinanceManager
//
//  Reusable category row component for displaying categories in lists
//

import SwiftUI

struct CategoryRow: View {
    let category: CustomCategory
    let isDefault: Bool
    let budgetProgress: BudgetProgress?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: AppSpacing.md) {
                    // Иконка с бюджетным прогрессом
                    ZStack {
                        // Budget progress stroke (if budget exists)
                        if let progress = budgetProgress {
                            Circle()
                                .trim(from: 0, to: min(progress.percentage / 100, 1.0))
                                .stroke(
                                    progress.isOverBudget ? AppColors.destructive : AppColors.success,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: AppIconSize.categoryIcon, height: AppIconSize.categoryIcon)
                                .animation(.easeInOut(duration: AppAnimation.standard), value: progress.percentage)
                        }

                        // Иконка
                        Circle()
                            .fill(category.color.opacity(0.2))
                            .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                            .overlay(
                                Group {
                                    if case .sfSymbol(let symbolName) = category.iconSource {
                                        Image(systemName: symbolName)
                                            .font(.system(size: AppIconSize.md))
                                            .foregroundStyle(category.color)
                                    }
                                }
                            )
                            .overlay(
                                Circle()
                                    .stroke(category.color, lineWidth: 2)
                            )
                    }

                    // Название и бюджет
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(category.name)
                            .font(AppTypography.h4)

                        if let progress = budgetProgress {
                            HStack(spacing: AppSpacing.xs) {
                                HStack(spacing: 0) {
                                    FormattedAmountText(
                                        amount: progress.spent,
                                        currency: "₸",
                                        fontSize: AppTypography.bodySmall,
                                        color: progress.isOverBudget ? .red : .secondary
                                    )
                                    Text(" / ")
                                        .font(AppTypography.bodySmall)
                                        .foregroundStyle(progress.isOverBudget ? .red : .secondary)
                                    FormattedAmountText(
                                        amount: progress.budgetAmount,
                                        currency: "₸",
                                        fontSize: AppTypography.bodySmall,
                                        color: progress.isOverBudget ? .red : .secondary
                                    )
                                }

                                Text("(\(Int(progress.percentage))%)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                        } else if category.type == .expense {
                            Text(String(localized: "No budget set"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isDefault {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "button.delete"), systemImage: "trash")
                }
            }
        }
    }

// formatAmount больше не нужен - используем FormattedAmountText

#Preview {
    let sampleCategory = CustomCategory(
        id: "test",
        name: "Food",
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#3b82f6",
        type: .expense
    )

    List {
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
