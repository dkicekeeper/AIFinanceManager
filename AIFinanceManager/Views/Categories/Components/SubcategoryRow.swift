//
//  SubcategoryRow.swift
//  AIFinanceManager
//
//  Reusable subcategory row component with checkbox
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Subcategory selection row with checkmark indicator
/// Now built on top of UniversalRow for consistency
struct SubcategoryRow: View {
    let subcategory: Subcategory
    @Binding var isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        UniversalRow(
            config: RowConfiguration(
                spacing: AppSpacing.md,
                verticalPadding: AppSpacing.sm,
                horizontalPadding: AppSpacing.lg,
                backgroundColor: .clear,
                cornerRadius: 0
            )
        ) {
            Text(subcategory.name)
                .font(AppTypography.bodyLarge)
        } trailing: {
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(AppColors.accent)
                    .font(AppTypography.bodyLarge)
            }
        }
        .selectableRow(isSelected: isSelected, action: onToggle)
    }
}

#Preview {
    @Previewable @State var isSelected = false
    
    return SubcategoryRow(
        subcategory: Subcategory(id: "1", name: "Groceries"),
        isSelected: $isSelected,
        onToggle: {
            isSelected.toggle()
        }
    )
    .padding()
}
