//
//  AccountCard.swift
//  AIFinanceManager
//
//  Reusable account card component
//

import SwiftUI

struct AccountCard: View {
    let account: Account
    let adaptiveTextColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                account.bankLogo.image(size: AppIconSize.xl)
                    .foregroundStyle(adaptiveTextColor.opacity(0.7))
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundStyle(adaptiveTextColor)
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(AppTypography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(adaptiveTextColor)
                }
            }
            .padding(AppSpacing.lg)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadowStyle(AppShadow.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview("Account Card") {
    AccountCard(
        account: Account(name: "Main Account", balance: 1000, currency: "USD", bankLogo: .none),
        adaptiveTextColor: .primary,
        onTap: {}
    )
    .padding()
}
