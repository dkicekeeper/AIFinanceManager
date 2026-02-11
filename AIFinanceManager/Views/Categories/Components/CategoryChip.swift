//
//  CategoryChip.swift
//  AIFinanceManager
//
//  Reusable category chip/button component
//

import SwiftUI

struct CategoryChip: View {
    let category: String
    let type: TransactionType
    let customCategories: [CustomCategory]
    let isSelected: Bool
    let onTap: () -> Void
    
    // Budget support
    let budgetProgress: BudgetProgress?
    let budgetAmount: Double?
    
    @State private var isPressed = false

    // OPTIMIZATION: Use cached style data instead of recreating on every render
    private var styleData: CategoryStyleData {
        CategoryStyleHelper.cached(category: category, type: type, customCategories: customCategories)
    }

    private var customCategory: CustomCategory? {
        customCategories.first { $0.name.lowercased() == category.lowercased() && $0.type == type }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                Text(category)
                    .font(AppTypography.bodyLarge)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ZStack {
                    // Budget progress stroke (if budget exists and is expense)
                    if let progress = budgetProgress, type == .expense {
                        Circle()
                            .trim(from: 0, to: min(progress.percentage / 100, 1.0))
                            .stroke(
                                progress.isOverBudget ? Color.red : Color.green,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: AppIconSize.budgetRing, height: AppIconSize.budgetRing)
                            .animation(.easeInOut(duration: 0.3), value: progress.percentage)
                    }
                    
                    Group {
                        if #available(iOS 26, *) {
                            ZStack {
                                Circle()
                                    .foregroundStyle(.clear)
                                    .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                                    .glassEffect(.regular
                                        .tint(isSelected ? styleData.coinColor : styleData.coinColor.opacity(1.0))
                                    )
                                    .allowsHitTesting(false)

                                Image(systemName: styleData.iconName)
                                    .font(.title2)
                                    .foregroundStyle(styleData.iconColor)

                                Circle()
                                    .stroke(isSelected ? styleData.coinBorderColor : Color.clear, lineWidth: 3)
                                    .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                                    .allowsHitTesting(false)
                            }
                        } else {
                            Circle()
                                .fill(isSelected ? styleData.coinColor.opacity(0.2) : Color(.systemGray6))
                                .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                                .overlay(
                                    Image(systemName: styleData.iconName)
                                        .font(.title2)
                                        .foregroundStyle(styleData.iconColor)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? styleData.coinBorderColor : Color.clear, lineWidth: 3)
                                )
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain) 
        .accessibilityLabel("\(category) category")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(budgetProgress != nil ? "Budget: \(Int(budgetProgress!.percentage))% spent" : "")
    }
}

#Preview("Category Chip") {
    VStack(spacing: 20) {
        CategoryChip(
            category: "Food",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: nil,
            budgetAmount: nil
        )
        
        CategoryChip(
            category: "Food",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 5000),
            budgetAmount: 10000
        )
        
        CategoryChip(
            category: "Auto",
            type: .expense,
            customCategories: [],
            isSelected: false,
            onTap: {},
            budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 12000),
            budgetAmount: 10000
        )
    }
    .padding()
}
