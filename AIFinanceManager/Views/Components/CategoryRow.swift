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
            HStack(spacing: AppSpacing.md) {
                // Иконка с бюджетным прогрессом
                ZStack {
                    // Budget progress stroke (if budget exists)
                    if let progress = budgetProgress {
                        Circle()
                            .trim(from: 0, to: min(progress.percentage / 100, 1.0))
                            .stroke(
                                progress.isOverBudget ? Color.red : Color.green,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 50, height: 50)
                            .animation(.easeInOut(duration: 0.3), value: progress.percentage)
                    }
                    
                    // Иконка
                    Circle()
                        .fill(category.color.opacity(0.2))
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                        .overlay(
                            Image(systemName: category.iconName)
                                .font(.system(size: AppIconSize.md))
                                .foregroundColor(category.color)
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
                            Text("\(formatAmount(progress.spent)) / \(formatAmount(progress.budgetAmount))₸")
                                .font(AppTypography.caption)
                                .foregroundColor(progress.isOverBudget ? .red : .secondary)
                            
                            Text("(\(Int(progress.percentage))%)")
                                .font(AppTypography.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if category.type == .expense {
                        Text(String(localized: "No budget set"))
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !isDefault {
                    Button(role: .destructive, action: onDelete) {
                        Label(String(localized: "button.delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "%.0f", amount)
        } else {
            return String(format: "%.0f", amount)
    }
}

#Preview {
    let sampleCategory = CustomCategory(
        id: "test",
        name: "Food",
        iconName: "fork.knife",
        colorHex: "#3b82f6",
        type: .expense
    )
    
    return List {
        CategoryRow(
            category: sampleCategory,
            isDefault: false,
            budgetProgress: nil,
            onEdit: { print("Edit tapped") },
            onDelete: { print("Delete tapped") }
        )
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
