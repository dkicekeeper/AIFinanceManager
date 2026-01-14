//
//  AccountCard.swift
//  AIFinanceManager
//
//  Reusable account card component
//

import SwiftUI

struct AccountCard: View {
    let account: Account
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                account.bankLogo.image(size: AppIconSize.xl)
//                    .foregroundStyle(.primary.opacity(0.7))
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundColor(.primary)
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(AppTypography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding(AppSpacing.lg)
        }
        .glassEffect(in: .rect(cornerRadius: AppRadius.pill))
    }
}

#Preview("Account Card") {
    AccountCard(
        account: Account(name: "Main Account", balance: 1000, currency: "USD", bankLogo: .none),
        onTap: {}
    )
    .padding()
}
