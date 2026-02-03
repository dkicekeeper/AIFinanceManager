//
//  AccountsCarousel.swift
//  AIFinanceManager
//
//  Horizontal scrollable carousel of account cards
//

import SwiftUI

/// Displays accounts in a horizontal scrollable carousel
/// Extracted from ContentView for reusability and cleaner structure
struct AccountsCarousel: View {
    // MARK: - Properties
    let accounts: [Account]
    let onAccountTap: (Account) -> Void
    @ObservedObject var balanceCoordinator: BalanceCoordinator

    // MARK: - Body
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(accounts) { account in
                    AccountCard(
                        account: account,
                        onTap: {
                            HapticManager.light()
                            onAccountTap(account)
                        },
                        balanceCoordinator: balanceCoordinator
                    )
                    // Use balance from coordinator for proper identity tracking
                    .id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .scrollClipDisabled()
        .screenPadding()
    }
}

// MARK: - Preview
#Preview {
    let coordinator = AppCoordinator()

    return AccountsCarousel(
        accounts: [
            Account(
                id: "1",
                name: "Kaspi Bank",
                currency: "KZT",
                bankLogo: .kaspi,
                depositInfo: nil,
                initialBalance: 150000
            ),
            Account(
                id: "2",
                name: "Halyk Bank",
                currency: "KZT",
                bankLogo: .halykBank,
                depositInfo: nil,
                initialBalance: 250000
            )
        ],
        onAccountTap: { _ in },
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
}
