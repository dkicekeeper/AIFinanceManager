//
//  AccountSelectorView.swift
//  AIFinanceManager
//
//  Reusable account selector component with horizontal scroll
//

import SwiftUI

struct AccountSelectorView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    
    init(
        accounts: [Account],
        selectedAccountId: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil
    ) {
        self.accounts = accounts
        self._selectedAccountId = selectedAccountId
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if accounts.isEmpty {
                if let message = emptyStateMessage {
                    Text(message)
                        .font(AppTypography.bodyLarge)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(accounts) { account in
                            AccountRadioButton(
                                account: account,
                                isSelected: selectedAccountId == account.id,
                                onTap: {
                                    selectedAccountId = account.id
                                    onSelectionChange?(account.id)
                                }
                            )
                        }
                    }
                    
                }
                .padding(AppSpacing.lg)
                .scrollClipDisabled()
            }
            
            if let warning = warningMessage {
                WarningMessageView(message: warning)
            }
        }
//        .background(.primary .opacity(0.05))
    }
}

#Preview {
    @Previewable @State var selectedAccountId: String? = nil
    
    return VStack {
        AccountSelectorView(
            accounts: [
                Account(name: "Main Account", balance: 1000, currency: "USD", bankLogo: .none),
                Account(name: "Savings", balance: 5000, currency: "USD", bankLogo: .none)
            ],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: nil,
            warningMessage: nil
        )
        
        AccountSelectorView(
            accounts: [],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: "No accounts available",
            warningMessage: nil
        )
        
        AccountSelectorView(
            accounts: [
                Account(name: "Main Account", balance: 1000, currency: "USD", bankLogo: .none)
            ],
            selectedAccountId: $selectedAccountId,
            emptyStateMessage: nil,
            warningMessage: "Please select an account"
        )
    }
    .padding()
}
