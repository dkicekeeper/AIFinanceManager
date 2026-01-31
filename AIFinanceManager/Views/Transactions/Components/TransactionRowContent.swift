//
//  TransactionRowContent.swift
//  AIFinanceManager
//
//  Reusable base component for rendering transaction row content
//  Used by both TransactionCard and DepositTransactionRow
//

import SwiftUI

/// Base component for rendering transaction row content without interactions
struct TransactionRowContent: View {
    let transaction: Transaction
    let currency: String
    let customCategories: [CustomCategory]
    let accounts: [Account]
    let showIcon: Bool
    let showDescription: Bool
    let depositAccountId: String?
    let isPlanned: Bool
    let linkedSubcategories: [Subcategory]

    init(
        transaction: Transaction,
        currency: String,
        customCategories: [CustomCategory] = [],
        accounts: [Account] = [],
        showIcon: Bool = true,
        showDescription: Bool = true,
        depositAccountId: String? = nil,
        isPlanned: Bool = false,
        linkedSubcategories: [Subcategory] = []
    ) {
        self.transaction = transaction
        self.currency = currency
        self.customCategories = customCategories
        self.accounts = accounts
        self.showIcon = showIcon
        self.showDescription = showDescription
        self.depositAccountId = depositAccountId
        self.isPlanned = isPlanned
        self.linkedSubcategories = linkedSubcategories
    }

    private var isFutureDate: Bool {
        let dateFormatter = DateFormatters.dateFormatter
        guard let transactionDate = dateFormatter.date(from: transaction.date) else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        return transactionDate > today
    }

    private var styleHelper: CategoryStyleHelper {
        CategoryStyleHelper(category: transaction.category, type: transaction.type, customCategories: customCategories)
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon
            if showIcon {
                if isPlanned {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                        .font(AppTypography.caption)
                } else {
                    TransactionIconView(transaction: transaction, styleHelper: styleHelper)
                }
            }

            // Info
            if showDescription {
                TransactionInfoView(
                    transaction: transaction,
                    accounts: accounts,
                    linkedSubcategories: linkedSubcategories
                )
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    if !transaction.description.isEmpty {
                        Text(transaction.description)
                            .font(AppTypography.body)
                    }
                    Text(formatDate(transaction.date))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(isPlanned ? .blue : .secondary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                if transaction.type == .internalTransfer {
                    transferAmountView
                } else {
                    FormattedAmountView(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        prefix: amountPrefix,
                        color: amountColor
                    )

                    // Multi-currency support
                    if let targetCurrency = transaction.targetCurrency,
                       let targetAmount = transaction.targetAmount,
                       targetCurrency != transaction.currency {
                        HStack(spacing: 0) {
                            Text("(")
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(amountColor.opacity(0.7))
                            FormattedAmountView(
                                amount: targetAmount,
                                currency: targetCurrency,
                                prefix: "",
                                color: amountColor.opacity(0.7)
                            )
                            Text(")")
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(amountColor.opacity(0.7))
                        }
                    }
                }
            }
        }
        .opacity(isFutureDate ? 0.5 : 1.0)
    }

    // MARK: - Transfer Amount View

    @ViewBuilder
    private var transferAmountView: some View {
        let sourceAccount: Account? = transaction.accountId.flatMap { sourceId in
            accounts.first(where: { $0.id == sourceId })
        }
        let targetAccount: Account? = transaction.targetAccountId.flatMap { targetId in
            accounts.first(where: { $0.id == targetId })
        }

        if let source = sourceAccount {
            let sourceCurrency = source.currency
            let sourceAmount = transaction.convertedAmount ?? transaction.amount

            if let target = targetAccount {
                let targetCurrency = transaction.targetCurrency ?? target.currency
                let targetAmount = transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount

                // For deposits: show + or - based on direction
                if let depositId = depositAccountId {
                    let isIncoming = transaction.targetAccountId == depositId
                    FormattedAmountView(
                        amount: isIncoming ? targetAmount : sourceAmount,
                        currency: isIncoming ? targetCurrency : sourceCurrency,
                        prefix: isIncoming ? "+" : "-",
                        color: isIncoming ? .green : .primary
                    )
                } else {
                    // For regular transfers: show both amounts
                    VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                        FormattedAmountView(
                            amount: sourceAmount,
                            currency: sourceCurrency,
                            prefix: "-",
                            color: .primary
                        )

                        FormattedAmountView(
                            amount: targetAmount,
                            currency: targetCurrency,
                            prefix: "+",
                            color: .green
                        )
                    }
                }
            } else {
                FormattedAmountView(
                    amount: sourceAmount,
                    currency: sourceCurrency,
                    prefix: "-",
                    color: .primary
                )
            }
        } else {
            FormattedAmountView(
                amount: transaction.amount,
                currency: transaction.currency,
                prefix: "",
                color: amountColor
            )
        }
    }

    // MARK: - Helpers

    private var amountColor: Color {
        if isPlanned {
            return .blue
        }

        // For deposits with depositAccountId
        if let depositId = depositAccountId, transaction.type == .internalTransfer {
            let isIncoming = transaction.targetAccountId == depositId
            return isIncoming ? .green : .primary
        }

        switch transaction.type {
        case .income:
            return .green
        case .expense:
            return .primary
        case .internalTransfer:
            return .primary
        case .depositTopUp, .depositInterestAccrual:
            return .green
        case .depositWithdrawal:
            return .primary
        }
    }

    private var amountPrefix: String {
        if isPlanned {
            return "+"
        }

        // For deposits with depositAccountId
        if let depositId = depositAccountId {
            if transaction.type == .depositInterestAccrual {
                return "+"
            } else if transaction.type == .internalTransfer {
                let isIncoming = transaction.targetAccountId == depositId
                return isIncoming ? "+" : "-"
            }
        }

        switch transaction.type {
        case .income:
            return "+"
        case .expense:
            return "-"
        case .internalTransfer:
            return ""
        case .depositTopUp, .depositInterestAccrual:
            return "+"
        case .depositWithdrawal:
            return "-"
        }
    }

    private func formatDate(_ dateString: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else {
            return dateString
        }
        return DateFormatters.displayDateFormatter.string(from: date)
    }
}

#Preview("Transaction Row Content - Regular") {
    let coordinator = AppCoordinator()
    let sampleTransaction = Transaction(
        id: "test-1",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Test transaction",
        amount: 1000,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? ""
    )

    TransactionRowContent(
        transaction: sampleTransaction,
        currency: "KZT",
        customCategories: coordinator.categoriesViewModel.customCategories,
        accounts: coordinator.accountsViewModel.accounts
    )
    .padding()
}

#Preview("Transaction Row Content - Planned") {
    let sampleTransaction = Transaction(
        id: "test-2",
        date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(7 * 24 * 60 * 60)),
        description: "Future interest",
        amount: 1250,
        currency: "KZT",
        type: .depositInterestAccrual,
        category: "Interest",
        accountId: "deposit-1"
    )

    TransactionRowContent(
        transaction: sampleTransaction,
        currency: "KZT",
        isPlanned: true
    )
    .padding()
}
