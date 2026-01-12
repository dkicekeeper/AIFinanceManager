//
//  DateSectionHeader.swift
//  AIFinanceManager
//
//  Reusable date section header component
//

import SwiftUI

struct DateSectionHeader: View {
    let dateKey: String
    let dayExpenses: Double
    let currency: String
    
    var body: some View {
        HStack {
            Text(dateKey)
                .font(AppTypography.bodySmall)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            if dayExpenses > 0 {
                Text("-" + Formatting.formatCurrency(dayExpenses, currency: currency))
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
        }
        .textCase(nil)
    }
}

#Preview("Date Header") {
    DateSectionHeader(
        dateKey: "Today",
        dayExpenses: 1250.50,
        currency: "USD"
    )
    .padding()
}
