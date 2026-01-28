//
//  DepositTransactionRow.swift
//  AIFinanceManager
//
//  Reusable deposit transaction row component
//

import SwiftUI

struct DepositTransactionRow: View {
    let transaction: Transaction
    let currency: String
    var depositAccountId: String?
    /// When true, renders a "planned" highlight (blue tint + clock icon)
    var isPlanned: Bool = false

    var body: some View {
        HStack {
            if isPlanned {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                    .font(AppTypography.caption)
            } else {
                Image(systemName: iconForTransactionType(transaction.type))
                    .foregroundColor(colorForTransactionType(transaction.type))
                    .font(AppTypography.caption)
                    .frame(width: AppIconSize.sm)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if !transaction.description.isEmpty {
                    Text(transaction.description)
                        .font(AppTypography.body)
                }
                Text(formatDate(transaction.date))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(isPlanned ? .blue : .secondary)
            }

            Spacer()

            Text(formatAmount(transaction))
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(isPlanned ? .blue : colorForTransactionType(transaction.type))
        }
        .padding(AppSpacing.sm)
        .background(isPlanned ? Color.blue.opacity(0.1) : AppColors.secondaryBackground)
        .cornerRadius(AppRadius.sm)
    }
    
    private func iconForTransactionType(_ type: TransactionType) -> String {
        switch type {
        case .internalTransfer:
            return "arrow.left.arrow.right.circle.fill"
        case .depositInterestAccrual:
            return "percent"
        default:
            return "circle"
        }
    }
    
    private func colorForTransactionType(_ type: TransactionType) -> Color {
        switch type {
        case .internalTransfer:
            return .blue
        case .depositInterestAccrual:
            return .green
        default:
            return .primary
        }
    }
    
    private func formatAmount(_ transaction: Transaction) -> String {
        // Для переводов определяем направление на основе depositAccountId
        if transaction.type == .depositInterestAccrual {
            return "+\(Formatting.formatCurrency(transaction.amount, currency: currency))"
        } else if transaction.type == .internalTransfer {
            // Если депозит - получатель, это пополнение (+)
            let isIncoming = transaction.targetAccountId == depositAccountId
            let sign = isIncoming ? "+" : "-"
            return "\(sign)\(Formatting.formatCurrency(transaction.amount, currency: currency))"
        }
        return Formatting.formatCurrency(transaction.amount, currency: currency)
    }
    
    private func formatDate(_ dateString: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else {
            return dateString
        }
        return DateFormatters.displayDateFormatter.string(from: date)
    }
}

#Preview("Deposit Transaction Row - Interest") {
    let sampleTransaction = Transaction(
        id: "test-1",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Interest accrual",
        amount: 1250.50,
        currency: "KZT",
        type: .depositInterestAccrual,
        category: "Interest",
        accountId: "deposit-1"
    )
    
    DepositTransactionRow(
        transaction: sampleTransaction,
        currency: "KZT",
        depositAccountId: "deposit-1"
    )
    .padding()
}

#Preview("Deposit Transaction Row - Transfer In") {
    let sampleTransaction = Transaction(
        id: "test-2",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Deposit top-up",
        amount: 50000,
        currency: "KZT",
        type: .internalTransfer,
        category: "Transfer",
        accountId: "account-1",
        targetAccountId: "deposit-1"
    )
    
    DepositTransactionRow(
        transaction: sampleTransaction,
        currency: "KZT",
        depositAccountId: "deposit-1"
    )
    .padding()
}

#Preview("Deposit Transaction Row - Transfer Out") {
    let sampleTransaction = Transaction(
        id: "test-3",
        date: DateFormatters.dateFormatter.string(from: Date()),
        description: "Transfer from deposit",
        amount: 20000,
        currency: "KZT",
        type: .internalTransfer,
        category: "Transfer",
        accountId: "deposit-1",
        targetAccountId: "account-1"
    )
    
    DepositTransactionRow(
        transaction: sampleTransaction,
        currency: "KZT",
        depositAccountId: "deposit-1"
    )
    .padding()
}
