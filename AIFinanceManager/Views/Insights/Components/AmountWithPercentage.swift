//
//  AmountWithPercentage.swift
//  AIFinanceManager
//
//  Trailing VStack with formatted amount + percentage caption.
//  Extracted from InsightDetailView and CategoryDeepDiveView (Phase 26).
//

import SwiftUI

/// Right-aligned column showing a monetary amount above a percentage caption.
/// Used in category breakdown rows and subcategory lists.
struct AmountWithPercentage: View {
    let amount: Double
    let currency: String
    let percentage: Double
    var amountFont: Font = AppTypography.body
    var amountWeight: Font.Weight = .semibold
    var amountColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: amountFont,
                fontWeight: amountWeight,
                color: amountColor
            )
            Text(String(format: "%.1f%%", percentage))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: AppSpacing.md) {
        AmountWithPercentage(amount: 85_000, currency: "KZT", percentage: 34.5)
        AmountWithPercentage(amount: 12_400, currency: "USD", percentage: 8.2)
    }
    .screenPadding()
}
