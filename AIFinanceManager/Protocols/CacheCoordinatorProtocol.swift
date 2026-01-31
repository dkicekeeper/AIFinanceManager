//
//  CacheCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Scope of cache invalidation
enum CacheInvalidationScope {
    case summaryAndCurrency  // Only summary + currency caches
    case aggregates          // Only aggregate cache
    case all                 // All caches (use with caution)
}

/// Protocol for coordinating all cache operations
/// Centralizes cache management that was scattered across TransactionsViewModel
@MainActor
protocol CacheCoordinatorProtocol {

    /// Invalidate caches based on scope
    /// - Parameter scope: Which caches to invalidate
    func invalidate(scope: CacheInvalidationScope)

    /// Rebuild aggregate cache (blocking, waits for completion)
    /// Use this when you need to ensure aggregates are rebuilt before continuing
    func rebuildAggregates(
        transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository
    ) async

    /// Rebuild aggregate cache in background (non-blocking, fire-and-forget)
    /// Use this when you want to trigger rebuild from synchronous context
    func rebuildAggregatesAsync(
        transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository,
        onComplete: @escaping () -> Void
    )

    /// Precompute currency conversions for all transactions
    /// - Parameters:
    ///   - transactions: Transactions to precompute
    ///   - baseCurrency: Base currency for conversions
    func precomputeCurrencyConversions(
        transactions: [Transaction],
        baseCurrency: String
    )
}
