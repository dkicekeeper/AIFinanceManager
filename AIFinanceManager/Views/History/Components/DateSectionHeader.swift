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
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            if dayExpenses > 0 {
                FormattedAmountText(
                    amount: dayExpenses,
                    currency: currency,
                    prefix: "-",
                    fontSize: AppTypography.bodySmall,
                    fontWeight: .semibold,
                    color: AppColors.textSecondary
                )
            }
        }
        .textCase(nil)
        .glassCardStyle()
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
