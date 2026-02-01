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
                        }
                    )
                    .id("\(account.id)-\(account.balance)")
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
    AccountsCarousel(
        accounts: [
            Account(
                id: "1",
                name: "Kaspi Bank",
                balance: 150000,
                currency: "KZT",
                bankLogo: .kaspi,
                depositInfo: nil
            ),
            Account(
                id: "2",
                name: "Halyk Bank",
                balance: 250000,
                currency: "KZT",
                bankLogo: .halykBank,
                depositInfo: nil
            )
        ],
        onAccountTap: { _ in }
    )
}
