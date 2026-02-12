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
    let balanceCoordinator: BalanceCoordinator
    /// Pre-computed interest accrued to today (from parent via DepositInterestService)
    var interestToday: Double? = nil
    /// Pre-computed next interest posting date (from parent via DepositInterestService)
    var nextPostingDate: Date? = nil

    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }

    var body: some View {
            HStack(spacing: AppSpacing.md) {
                // Логотип банка
                IconView(source: account.iconSource, size: AppIconSize.xl)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)

                    FormattedAmountText(
                        amount: balance,
                        currency: account.currency,
                        fontSize: AppTypography.bodySmall,
                        color: .secondary
                    )

                    if let interest = interestToday, interest > 0 {
                        HStack(spacing: 0) {
                            Text(String(localized: "account.interestToday").replacingOccurrences(of: "%@", with: ""))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)

                            FormattedAmountText(
                                amount: interest,
                                currency: account.currency,
                                fontSize: AppTypography.caption,
                                color: .secondary
                            )
                        }
                    }

                    if let posting = nextPostingDate {
                        let dateString = DateFormatters.displayDateFormatter.string(from: posting)
                        Text(String(format: String(localized: "account.nextPosting"), dateString))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if account.isDeposit {
                    Image(systemName: "banknote")
                        .foregroundStyle(.secondary)
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

#Preview {
    let sampleAccount = Account(
        id: "test",
        name: "Test Account",
        currency: "USD",
        iconSource: nil,
        initialBalance: 10000
    )
    let coordinator = AppCoordinator()

    List {
        AccountRow(
            account: sampleAccount,
            currency: "USD",
            onEdit: {},
            onDelete: {},
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
        )
        .padding(.horizontal)
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
