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
    
    @State private var isPressed = false
    
    private var styleHelper: CategoryStyleHelper {
        CategoryStyleHelper(category: category, type: type, customCategories: customCategories)
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                Circle()
                    .foregroundStyle(.clear)
                    .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                    .overlay(
                        Image(systemName: styleHelper.iconName)
                            .font(.title2)
                            .foregroundColor(styleHelper.iconColor)
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? styleHelper.coinBorderColor : Color.clear, lineWidth: 3)
                    )
                    .glassEffect(.regular
                           .tint(isSelected ? styleHelper.coinColor : styleHelper.coinColor.opacity(1.0))
                           .interactive()
                       )
                
                Text(category)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        
        .accessibilityLabel("\(category) category")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Category Chip") {
    CategoryChip(
        category: "Food",
        type: .expense,
        customCategories: [],
        isSelected: false,
        onTap: {}
    )
    .padding()
}
