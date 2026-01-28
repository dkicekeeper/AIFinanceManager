//
//  TransactionCurrencyService.swift
//  AIFinanceManager
//
//  Isolated service for currency conversion caching.
//  Pre-computes converted amounts from stored transaction data (no network calls).
//

import Foundation

/// Кэш конвертации валют для транзакций.
/// Использует только `convertedAmount`, записанный при создании транзакции.
@MainActor
class TransactionCurrencyService {

    // MARK: - Cache

    private var cache: [String: Double] = [:]
    private(set) var isInvalidated: Bool = true

    // MARK: - API

    /// Invalidate the conversion cache
    func invalidate() {
        isInvalidated = true
    }

    /// Precompute converted amounts for all transactions in `baseCurrency`.
    /// Uses only pre-stored `convertedAmount` — no network requests.
    func precompute(transactions: [Transaction], baseCurrency: String) {
        guard isInvalidated else { return }

        PerformanceProfiler.start("TransactionCurrencyService.precompute")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            var newCache: [String: Double] = [:]
            newCache.reserveCapacity(transactions.count)

            for tx in transactions {
                let key = "\(tx.id)_\(baseCurrency)"
                if tx.currency == baseCurrency {
                    newCache[key] = tx.amount
                } else {
                    newCache[key] = tx.convertedAmount ?? tx.amount
                }
            }

            await MainActor.run {
                self.cache = newCache
                self.isInvalidated = false
                PerformanceProfiler.end("TransactionCurrencyService.precompute")
            }
        }
    }

    /// Get cached converted amount for a transaction
    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        let key = "\(transactionId)_\(baseCurrency)"
        return cache[key]
    }

    /// Get converted amount from cache, falling back to transaction data
    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        if let cached = getConvertedAmount(transactionId: transaction.id, to: baseCurrency) {
            return cached
        }
        if transaction.currency == baseCurrency {
            return transaction.amount
        }
        return transaction.convertedAmount ?? transaction.amount
    }
}
