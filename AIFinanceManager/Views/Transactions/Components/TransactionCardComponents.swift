//
//  TransactionCardComponents.swift
//  AIFinanceManager
//
//  Extracted components from TransactionCard for better modularity
//

import SwiftUI

// MARK: - Transaction Icon View

struct TransactionIconView: View {
    let transaction: Transaction
    let styleHelper: CategoryStyleHelper
    
    var body: some View {
        ZStack {
            Circle()
                .fill(transaction.type == .internalTransfer ? Color.blue.opacity(0.2) : styleHelper.lightBackgroundColor)
                .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                .overlay(
                    Image(systemName: styleHelper.iconName)
                        .font(.system(size: AppIconSize.md))
                        .foregroundColor(transaction.type == .internalTransfer ? Color.blue : styleHelper.primaryColor)
                )
            
            // Recurring badge
            if transaction.recurringSeriesId != nil {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: AppIconSize.sm))
                    .foregroundColor(.blue)
                    .padding(AppSpacing.xs)
                    .background(Color.white)
                    .clipShape(Circle())
                    .offset(x: 16, y: 16)
            }
        }
    }
}

// MARK: - Transaction Info View

struct TransactionInfoView: View {
    let transaction: Transaction
    let accounts: [Account]
    let linkedSubcategories: [Subcategory]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Category name
            Text(transaction.category)
                .font(AppTypography.h4)
            
            // Subcategories
            if !linkedSubcategories.isEmpty {
                Text(linkedSubcategories.map { $0.name }.joined(separator: ", "))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.primary)
            }
            
            // Account info or transfer info
            if transaction.type == .internalTransfer {
                TransferAccountInfo(transaction: transaction, accounts: accounts)
            } else {
                RegularAccountInfo(transaction: transaction, accounts: accounts)
            }
            
            // Description
            if !transaction.description.isEmpty {
                Text(transaction.description)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Transfer Account Info

struct TransferAccountInfo: View {
    let transaction: Transaction
    let accounts: [Account]

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            // Source account
            if let sourceId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                // Account exists - show with logo
                HStack(spacing: AppSpacing.xs) {
                    sourceAccount.bankLogo.image(size: AppIconSize.sm)
                    Text(sourceAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            } else if let accountName = transaction.accountName {
                // Account was deleted - show name only
                Text(accountName)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
                    .italic()
            }

            Image(systemName: "arrow.right")
                .font(.system(size: AppIconSize.sm))
                .foregroundColor(.secondary)

            // Target account
            if let targetId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetId }) {
                // Account exists - show with logo
                HStack(spacing: AppSpacing.xs) {
                    targetAccount.bankLogo.image(size: AppIconSize.sm)
                    Text(targetAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            } else if let targetAccountName = transaction.targetAccountName {
                // Account was deleted - show name only
                Text(targetAccountName)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Regular Account Info

struct RegularAccountInfo: View {
    let transaction: Transaction
    let accounts: [Account]

    var body: some View {
        if let accountId = transaction.accountId,
           let account = accounts.first(where: { $0.id == accountId }) {
            // Account exists - show with logo
            HStack(spacing: AppSpacing.xs) {
                account.bankLogo.image(size: AppIconSize.sm)
                Text(account.name)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }
        } else if let accountName = transaction.accountName {
            // Account was deleted - show name only without logo
            Text(accountName)
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .italic()
        }
    }
}

#Preview("Transaction Icon") {
    TransactionIconView(
        transaction: Transaction(
            id: "1",
            date: "2024-01-01",
            description: "Test",
            amount: 100,
            currency: "USD",
            type: .expense,
            category: "Food"
        ),
        styleHelper: CategoryStyleHelper(category: "Food", type: .expense, customCategories: [])
    )
    .padding()
}
