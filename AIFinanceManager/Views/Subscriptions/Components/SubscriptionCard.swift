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
            // Logo - показываем сохраненный brandLogo, иконку или fallback
            if let brandLogo = subscription.brandLogo {
                brandLogo.image(size: AppIconSize.xxl)
            } else if let brandId = subscription.brandId, !brandId.isEmpty {
                // Проверяем, является ли brandId иконкой (начинается с "sf:" или "icon:")
                if brandId.hasPrefix("sf:") {
                    let iconName = String(brandId.dropFirst(3))
                    Image(systemName: iconName)
                        .fallbackIconStyle(size: AppIconSize.xxl)
                } else if brandId.hasPrefix("icon:") {
                    let iconName = String(brandId.dropFirst(5))
                    Image(systemName: iconName)
                        .fallbackIconStyle(size: AppIconSize.xxl)
                } else {
                    // Если есть brandId (название бренда), показываем через BrandLogoView
                    BrandLogoView(brandName: brandId, size: AppIconSize.xxl)
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                }
            } else {
                // Fallback
                Image(systemName: "creditcard")
                    .fallbackIconStyle(size: AppIconSize.xxl)
            }
            
            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subscription.description)
                    .font(AppTypography.bodyLarge.weight(.semibold))
                
                Text(Formatting.formatCurrency(
                    NSDecimalNumber(decimal: subscription.amount).doubleValue,
                    currency: subscription.currency
                ))
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                
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
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
            case .archived:
                Image(systemName: "archive.circle.fill")
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
