//
//  SubcategorySearchButton.swift
//  AIFinanceManager
//
//  Reusable subcategory search button component
//

import SwiftUI

struct SubcategorySearchButton: View {
    let title: String
    let action: () -> Void
    
    init(
        title: String = String(localized: "transactionForm.searchSubcategories"),
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(title)
            }
            .font(AppTypography.body)
            .foregroundColor(.blue)
        }
    }
}

#Preview {
    SubcategorySearchButton {
        print("Search tapped")
    }
    .padding()
}
