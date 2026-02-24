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
    let balanceCoordinator: BalanceCoordinator
    var namespace: Namespace.ID

    // MARK: - Body
    var body: some View {
        UniversalCarousel(config: .cards) {
            ForEach(accounts.sortedByOrder()) { account in
                AccountCard(
                    account: account,
                    balanceCoordinator: balanceCoordinator,
                    namespace: namespace
                )
                // Use balance from coordinator for proper identity tracking
                .id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")
            }
        }
        .screenPadding()
    }
}

// MARK: - Preview
#Preview {
    @Previewable @Namespace var ns
    let coordinator = AppCoordinator()

    return NavigationStack {
        AccountsCarousel(
            accounts: [
                Account(
                    id: "1",
                    name: "Kaspi Bank",
                    currency: "KZT",
                    iconSource: .bankLogo(.kaspi),
                    depositInfo: nil,
                    initialBalance: 150000
                ),
                Account(
                    id: "2",
                    name: "Halyk Bank",
                    currency: "KZT",
                    iconSource: .bankLogo(.halykBank),
                    depositInfo: nil,
                    initialBalance: 250000
                )
            ],
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!,
            namespace: ns
        )
    }
}
