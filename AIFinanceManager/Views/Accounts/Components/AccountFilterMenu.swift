//
//  AccountFilterMenu.swift
//  AIFinanceManager
//
//  Reusable account filter menu component
//

import SwiftUI

struct AccountFilterMenu: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let balanceCoordinator: BalanceCoordinator

    var body: some View {
        Menu {
            Button(action: { selectedAccountId = nil }) {
                HStack {
                    Text("Все счета")
                    Spacer()
                    if selectedAccountId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            ForEach(accounts) { account in
                Button(action: { selectedAccountId = account.id }) {
                    HStack(spacing: AppSpacing.sm) {
                        BrandLogoDisplayView(iconSource: account.iconSource, size: AppIconSize.md)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(AppTypography.bodySmall)
                            let balance = balanceCoordinator.balances[account.id] ?? 0
                            Text(Formatting.formatCurrencySmart(balance, currency: account.currency))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedAccountId == account.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let selectedAccount = accounts.first(where: { $0.id == selectedAccountId })
            HStack(spacing: AppSpacing.sm) {
                if let account = selectedAccount {
                    BrandLogoDisplayView(iconSource: account.iconSource, size: AppIconSize.sm)
                }
                Text(selectedAccountId == nil ? "Все счета" : (selectedAccount?.name ?? "Все счета"))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle(isSelected: selectedAccountId != nil)
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()

    return AccountFilterMenu(
        accounts: [],
        selectedAccountId: .constant(nil),
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
    .padding()
}
