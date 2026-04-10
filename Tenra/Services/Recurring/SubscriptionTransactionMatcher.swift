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
    /// matching the subscription currency, and not already linked to any recurring series.
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

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.currency == currency else { return false }
                guard tx.amount >= lowerBound && tx.amount <= upperBound else { return false }
                guard tx.recurringSeriesId == nil else { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }
}
