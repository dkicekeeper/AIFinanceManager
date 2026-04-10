//
//  SubscriptionTransactionMatcher.swift
//  Tenra
//
//  Finds existing transactions that match a subscription's payment pattern.
//  Used to retroactively link manually entered transactions to a subscription.
//

import Foundation

/// Finds existing transactions that match a subscription's payment pattern.
nonisolated enum SubscriptionTransactionMatcher {

    /// Default tolerance: +/-10% of subscription amount.
    static let defaultTolerance: Double = 0.10

    /// Returns expense transactions whose amount matches the subscription's amount,
    /// in the subscription's currency OR in any other currency (via convertedAmount).
    /// - `exactMatch: false` (default): amount within ±`tolerance`
    /// - `exactMatch: true`: amount must equal subscription amount exactly
    /// Results are sorted chronologically.
    static func findCandidates(
        for subscription: RecurringSeries,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance,
        exactMatch: Bool = false
    ) -> [Transaction] {
        let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
        let currency = subscription.currency

        let lowerBound = exactMatch ? amount : amount * (1.0 - tolerance)
        let upperBound = exactMatch ? amount : amount * (1.0 + tolerance)

        // Also match via convertedAmount for cross-currency transactions.
        // E.g. subscription is $100 USD → transaction is 50 000 KZT with convertedAmount=100 USD.
        // We check: if tx.currency == subscription.currency → match on tx.amount.
        // Otherwise → match on tx.convertedAmount (the amount in the account's currency
        // which may equal the subscription amount if the account is in subscription currency).
        // Also try the reverse: subscription amount converted to tx currency via convertedAmount.
        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.recurringSeriesId == nil else { return false }

                if tx.currency == currency {
                    // Same currency — direct amount match
                    return tx.amount >= lowerBound && tx.amount <= upperBound
                } else {
                    // Cross-currency: check if convertedAmount matches subscription amount
                    // convertedAmount stores the amount in the account's currency
                    if let converted = tx.convertedAmount,
                       converted >= lowerBound && converted <= upperBound {
                        return true
                    }
                    // Also check targetAmount (used for multi-currency)
                    if let targetAmount = tx.targetAmount,
                       targetAmount >= lowerBound && targetAmount <= upperBound {
                        return true
                    }
                    return false
                }
            }
            .sorted { $0.date < $1.date }
    }
}
