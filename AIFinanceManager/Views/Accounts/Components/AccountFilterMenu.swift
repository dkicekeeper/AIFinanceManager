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
                        account.bankLogo.image(size: AppIconSize.md)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(AppTypography.bodySmall)
                            Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
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
                    account.bankLogo.image(size: AppIconSize.sm)
                }
                Text(selectedAccountId == nil ? "Все счета" : (selectedAccount?.name ?? "Все счета"))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle()
        }
    }
}

#Preview {
    AccountFilterMenu(
        accounts: [],
        selectedAccountId: .constant(nil)
    )
    .padding()
}
