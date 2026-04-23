//
//  LoanTransactionMatcher.swift
//  Tenra
//
//  Finds existing transactions that match a loan's payment pattern.
//  Used during loan onboarding to identify past payments the user
//  already recorded as regular expenses.
//

import Foundation

/// Finds existing transactions that match a loan's payment pattern.
nonisolated enum LoanTransactionMatcher {

    /// Default tolerance: +/-30% of monthly payment (matches subscription matcher).
    /// Covers rate adjustments and rounding over long-term loans.
    static let defaultTolerance: Double = 0.30

    /// Returns expense transactions whose amount matches the loan's `monthlyPayment`,
    /// dated after the loan start. Respects `AmountMatchMode`:
    /// - `.all`:       every expense dated after loan start (regardless of amount)
    /// - `.tolerance`: amount within ±`tolerance`
    /// - `.exact`:     amount equals `monthlyPayment` exactly
    /// Results are sorted chronologically (oldest first).
    static func findCandidates(
        for loan: Account,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance,
        mode: AmountMatchMode = .tolerance
    ) -> [Transaction] {
        guard let loanInfo = loan.loanInfo else { return [] }

        let monthlyPayment = NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue
        let startDate = loanInfo.startDate
        let loanCurrency = loan.currency

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.currency == loanCurrency else { return false }
                guard tx.date >= startDate else { return false }

                switch mode {
                case .all:
                    return true
                case .tolerance:
                    let lower = monthlyPayment * (1.0 - tolerance)
                    let upper = monthlyPayment * (1.0 + tolerance)
                    return tx.amount >= lower && tx.amount <= upper
                case .exact:
                    return tx.amount == monthlyPayment
                }
            }
            .sorted { $0.date < $1.date }
    }
}
