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
    let styleData: CategoryStyleData

    var body: some View {
        ZStack {
            Circle()
                .fill(transaction.type == .internalTransfer ? Color.blue.opacity(0.2) : styleData.lightBackgroundColor)
                .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                .overlay(
                    Image(systemName: styleData.iconName)
                        .font(.system(size: AppIconSize.md))
                        .foregroundStyle(transaction.type == .internalTransfer ? Color.blue : styleData.primaryColor)
                )
            
            // Recurring badge
            if transaction.recurringSeriesId != nil {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: AppIconSize.sm))
                    .foregroundStyle(.blue)
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
                    .foregroundStyle(.primary)
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
                    .foregroundStyle(.secondary)
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
                    IconView(source: sourceAccount.iconSource, size: AppIconSize.sm)
                    Text(sourceAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            } else if let accountName = transaction.accountName {
                // Account was deleted - show name only
                Text(accountName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Image(systemName: "arrow.right")
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(.secondary)

            // Target account
            if let targetId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetId }) {
                // Account exists - show with logo
                HStack(spacing: AppSpacing.xs) {
                    IconView(source: targetAccount.iconSource, size: AppIconSize.sm)
                    Text(targetAccount.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            } else if let targetAccountName = transaction.targetAccountName {
                // Account was deleted - show name only
                Text(targetAccountName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
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
                IconView(source: account.iconSource, size: AppIconSize.sm)
                Text(account.name)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        } else if let accountName = transaction.accountName {
            // Account was deleted - show name only without logo
            Text(accountName)
                .font(AppTypography.bodySmall)
                .foregroundStyle(.secondary)
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
        styleData: CategoryStyleHelper.cached(category: "Food", type: .expense, customCategories: [])
    )
    .padding()
}
