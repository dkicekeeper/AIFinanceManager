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
                .font(AppTypography.body)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .font(AppTypography.body)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
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
