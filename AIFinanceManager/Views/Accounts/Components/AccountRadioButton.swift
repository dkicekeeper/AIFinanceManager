//
//  AccountRadioButton.swift
//  AIFinanceManager
//
//  Reusable account radio button component
//

import SwiftUI

struct AccountRadioButton: View {
    let account: Account
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                account.bankLogo.image(size: AppIconSize.lg)
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                }
            }
            .glassCardStyle()
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.pill, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
//        .glassCardStyle()
    }
}

#Preview {
    HStack {
        AccountRadioButton(
            account: Account(name: "Main Account", balance: 1000, currency: "USD", bankLogo: .none),
            isSelected: false,
            onTap: {}
        )
        AccountRadioButton(
            account: Account(name: "Savings", balance: 5000, currency: "USD", bankLogo: .none),
            isSelected: true,
            onTap: {}
        )
    }
    .padding()
}
