//
//  DepositTransactionRow.swift
//  AIFinanceManager
//
//  Reusable deposit transaction row component
//  Refactored to use TransactionRowContent base component
//

import SwiftUI

struct DepositTransactionRow: View {
    let transaction: Transaction
    let currency: String
    let accounts: [Account]
    var depositAccountId: String? = nil
    /// When true, renders a "planned" highlight (blue tint + clock icon)
    var isPlanned: Bool = false

    init(
        transaction: Transaction,
        currency: String,
        accounts: [Account] = [],
        depositAccountId: String? = nil,
        isPlanned: Bool = false
    ) {
        self.transaction = transaction
        self.currency = currency
        self.accounts = accounts
        self.depositAccountId = depositAccountId
        self.isPlanned = isPlanned
    }

    var body: some View {
        TransactionRowContent(
            transaction: transaction,
            currency: currency,
            accounts: accounts,
            showIcon: true,
            showDescription: false, // Use simple description rendering for deposits
            depositAccountId: depositAccountId,
            isPlanned: isPlanned
        )
        .padding(AppSpacing.sm)
        .background(isPlanned ? Color.blue.opacity(0.1) : AppColors.secondaryBackground)
        .cornerRadius(AppRadius.sm)
    }
}

#Preview("Deposit Transaction Row - Interest") {
    let coordinator = AppCoordinator()
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
        accounts: coordinator.accountsViewModel.accounts,
        depositAccountId: "deposit-1"
    )
    .padding()
}

#Preview("Deposit Transaction Row - Transfer In") {
    let coordinator = AppCoordinator()
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
        accounts: coordinator.accountsViewModel.accounts,
        depositAccountId: "deposit-1"
    )
    .padding()
}

#Preview("Deposit Transaction Row - Transfer Out") {
    let coordinator = AppCoordinator()
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
        accounts: coordinator.accountsViewModel.accounts,
        depositAccountId: "deposit-1"
    )
    .padding()
}

#Preview("Deposit Transaction Row - Planned") {
    let coordinator = AppCoordinator()
    let sampleTransaction = Transaction(
        id: "test-4",
        date: DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(7 * 24 * 60 * 60)),
        description: "Future interest",
        amount: 1250,
        currency: "KZT",
        type: .depositInterestAccrual,
        category: "Interest",
        accountId: "deposit-1"
    )

    DepositTransactionRow(
        transaction: sampleTransaction,
        currency: "KZT",
        accounts: coordinator.accountsViewModel.accounts,
        depositAccountId: "deposit-1",
        isPlanned: true
    )
    .padding()
}
