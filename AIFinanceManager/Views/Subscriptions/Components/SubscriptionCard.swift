//
//  SubscriptionCard.swift
//  AIFinanceManager
//
//  Reusable subscription card component
//

import SwiftUI

struct SubscriptionCard: View {
    let subscription: RecurringSeries
    let nextChargeDate: Date?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // REFACTORED 2026-02-02: Use BrandLogoDisplayView to eliminate duplication
            BrandLogoDisplayView(
                brandLogo: subscription.brandLogo,
                brandId: subscription.brandId,
                brandName: subscription.description, // fallback to description as brand name
                size: AppIconSize.xxl
            )
            
            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subscription.description)
                    .font(AppTypography.bodyLarge.weight(.semibold))

                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                    currency: subscription.currency,
                    fontSize: AppTypography.body,
                    color: .secondary
                )
                
                if let nextChargeDate = nextChargeDate {
                    Text(String(format: String(localized: "subscriptions.nextCharge"), formatDate(nextChargeDate)))
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            
            // Status indicator
            statusIndicator
        }
        .glassCardStyle()
    }
    
    private var statusIndicator: some View {
        Group {
            switch subscription.subscriptionStatus {
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTypography.h4)
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .font(AppTypography.h4)
                    .foregroundColor(.orange)
            case .archived:
                Image(systemName: "archive.circle.fill")
                    .font(AppTypography.h4)
                    .foregroundColor(.gray)
            case .none:
                EmptyView()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatters.displayDateFormatter
        return formatter.string(from: date)
    }
}

#Preview {
    SubscriptionCard(
        subscription: RecurringSeries(
            id: "1",
            amount: Decimal(9.99),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            accountId: "1",
            frequency: .monthly,
            startDate: DateFormatters.dateFormatter.string(from: Date()),
            kind: .subscription,
            brandId: "Netflix",
            status: .active
        ),
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
