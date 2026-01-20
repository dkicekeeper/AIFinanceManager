//
//  AccountRow.swift
//  AIFinanceManager
//
//  Reusable account row component for displaying accounts in lists
//

import SwiftUI

struct AccountRow: View {
    let account: Account
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        CardContainer {
            HStack(spacing: AppSpacing.md) {
                // Логотип банка
                account.bankLogo.image(size: AppIconSize.xl)
                
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                    
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                    
                    if let depositInfo = account.depositInfo {
                        let interestToToday = DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
                        if interestToToday > 0 {
                            let formattedAmount = Formatting.formatCurrency(NSDecimalNumber(decimal: interestToToday).doubleValue, currency: account.currency)
                            Text(String(format: String(localized: "account.interestToday"), formattedAmount))
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let nextPosting = DepositInterestService.nextPostingDate(depositInfo: depositInfo) {
                            let formatter = DateFormatters.displayDateFormatter
                            let dateString = formatter.string(from: nextPosting)
                            Text(String(format: String(localized: "account.nextPosting"), dateString))
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if account.isDeposit {
                    Image(systemName: "banknote")
                        .foregroundColor(.secondary)
                        .font(.system(size: AppIconSize.sm))
                }
            }
            
            .onTapGesture {
                onEdit()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "button.delete"), systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "test",
        name: "Test Account",
        balance: 10000,
        currency: "USD",
        bankLogo: .none
    )
    
    return List {
        AccountRow(
            account: sampleAccount,
            currency: "USD",
            onEdit: { print("Edit tapped") },
            onDelete: { print("Delete tapped") }
        )
        .padding(.horizontal)
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
