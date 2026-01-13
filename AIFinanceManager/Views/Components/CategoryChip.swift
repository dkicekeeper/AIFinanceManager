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
                    .fill(isSelected ? styleHelper.coinColor : styleHelper.coinColor.opacity(0.5))
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
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: AppAnimation.fast), value: isPressed)
                
                Text(category)
                    .font(AppTypography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
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
