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
    let balanceCoordinator: BalanceCoordinator

    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                account.bankLogo.image(size: AppIconSize.xl)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundStyle(.primary)

                    FormattedAmountText(
                        amount: balance,
                        currency: account.currency,
                        fontSize: AppTypography.bodySmall,
                        fontWeight: .semibold,
                        color: .primary
                    )
                }
            }
            .glassCardStyle()
        }
        .buttonStyle(.bounce)
        .accessibilityLabel(String(format: String(localized: "accessibility.accountCard.label"), account.name, Formatting.formatCurrency(balance, currency: account.currency)))
        .accessibilityHint(String(localized: "accessibility.accountCard.hint"))
    }
}

#Preview("Account Card") {
    let coordinator = AppCoordinator()

    return AccountCard(
        account: Account(name: "Main Account", currency: "USD", bankLogo: .none, initialBalance: 1000),
        onTap: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
    .padding()
}
