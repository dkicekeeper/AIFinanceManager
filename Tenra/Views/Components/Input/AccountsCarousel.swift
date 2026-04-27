//
//  AccountsCarousel.swift
//  Tenra
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
    let namespace: Namespace.ID

    // MARK: - Body
    var body: some View {
        // Snapshot the balances dict here — this view subscribes to it (parent of
        // AccountCard), so per-card body re-evals only happen when the row's specific
        // balance changes. Without this hoist, AccountCard would observe the whole
        // dict and every balance write would re-render every visible card.
        let balancesById = balanceCoordinator.balances
        UniversalCarousel(config: .cards) {
            ForEach(accounts.sortedByOrder()) { account in
                AccountCard(
                    account: account,
                    balance: balancesById[account.id] ?? 0,
                    namespace: namespace
                )
                .scrollTransition(.animated(.easeOut(duration: 0.3))) { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.75)
                        .scaleEffect(phase.isIdentity ? 1 : 0.95)
                }
                .id(account.id)
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
                    iconSource: .brandService("kaspi.kz"),
                    depositInfo: nil,
                    initialBalance: 150000
                ),
                Account(
                    id: "2",
                    name: "Halyk Bank",
                    currency: "KZT",
                    iconSource: .brandService("halykbank.kz"),
                    depositInfo: nil,
                    initialBalance: 250000
                )
            ],
            balanceCoordinator: coordinator.balanceCoordinator,
            namespace: ns
        )
    }
}
