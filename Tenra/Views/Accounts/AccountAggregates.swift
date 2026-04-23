//
//  AccountAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for AccountDetailView.
//  Lives in a `nonisolated enum` so the computation can run off MainActor if needed.
//

import Foundation

struct AccountAggregates: Equatable, Sendable {
    let totalTransactions: Int
    let totalIncome: Double      // in account currency
    let totalExpense: Double     // in account currency
}

nonisolated enum AccountAggregatesCalculator {
    /// Computes transaction count, total income, and total expense for a given account
    /// over the provided transaction list. Amounts are converted into `accountCurrency`
    /// when the transaction currency differs.
    ///
    /// Cases are enumerated explicitly (no `@unknown default`) so the compiler forces an
    /// update whenever `TransactionType` gains a new case.
    static func compute(
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction]
    ) -> AccountAggregates {
        var count = 0
        var income = 0.0
        var expense = 0.0
        for tx in transactions {
            let isSource = tx.accountId == accountId
            let isTarget = tx.targetAccountId == accountId
            guard isSource || isTarget else { continue }
            count += 1

            // For internal transfers, the incoming leg must be valued in the TARGET
            // currency using `targetAmount` when available (the source-currency amount
            // may be in a different currency from this account).
            let amount: Double
            if tx.type == .internalTransfer, isTarget,
               let targetAmount = tx.targetAmount,
               let targetCurrency = tx.targetCurrency {
                amount = convertIfNeeded(
                    amount: targetAmount,
                    from: targetCurrency,
                    to: accountCurrency,
                    stored: nil
                )
            } else {
                amount = convertIfNeeded(
                    amount: tx.amount,
                    from: tx.currency,
                    to: accountCurrency,
                    stored: tx.convertedAmount
                )
            }

            switch tx.type {
            case .income:
                if isSource { income += amount }
            case .expense:
                if isSource { expense += amount }
            case .internalTransfer:
                if isTarget { income += amount }
                if isSource { expense += amount }
            case .depositTopUp:
                // Top-up: source account (funding side) loses money, target deposit gains money.
                if isSource { expense += amount }
                if isTarget { income += amount }
            case .depositWithdrawal:
                // Withdrawal from deposit: source deposit decreases, target destination increases.
                if isSource { expense += amount }
                if isTarget { income += amount }
            case .depositInterestAccrual:
                // Interest is credited to the deposit account (source on most records).
                if isSource { income += amount }
                if isTarget { income += amount }
            case .loanPayment, .loanEarlyRepayment:
                // Payment from a regular account towards a loan.
                if isSource { expense += amount }
                if isTarget { income += amount }
            }
        }
        return AccountAggregates(
            totalTransactions: count,
            totalIncome: income,
            totalExpense: expense
        )
    }

    private static func convertIfNeeded(
        amount: Double,
        from: String,
        to: String,
        stored: Double?
    ) -> Double {
        if from == to { return amount }
        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: to) {
            return converted
        }
        return stored ?? amount
    }
}
