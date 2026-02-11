//
//  SubcategoryRow.swift
//  AIFinanceManager
//
//  Reusable subcategory row component with checkbox
//

import SwiftUI

struct SubcategoryRow: View {
    let subcategory: Subcategory
    @Binding var isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Text(subcategory.name)
                .font(AppTypography.bodyLarge)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .font(AppTypography.bodyLarge)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
//        .padding(AppSpacing.md)
//        .background(.primary .opacity(0.05))
        .padding(AppSpacing.lg)
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
