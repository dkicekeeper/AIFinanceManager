//
//  CacheCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Coordinator for all cache operations (summary, aggregate, currency)
/// Extracted from TransactionsViewModel (lines 143-380) to follow SRP
@MainActor
class CacheCoordinator: CacheCoordinatorProtocol {

    // MARK: - Dependencies

    private let cacheManager: TransactionCacheManager
    private let currencyService: TransactionCurrencyService
    private let aggregateCache: CategoryAggregateCache

    // MARK: - Initialization

    init(
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        aggregateCache: CategoryAggregateCache
    ) {
        self.cacheManager = cacheManager
        self.currencyService = currencyService
        self.aggregateCache = aggregateCache
    }

    // MARK: - CacheCoordinatorProtocol Implementation

    func invalidate(scope: CacheInvalidationScope) {
        switch scope {
        case .summaryAndCurrency:
            print("🔄 [CacheCoordinator] Invalidating summary/currency caches")
            cacheManager.invalidateAll()
            currencyService.invalidate()
            // NOTE: We do NOT clear aggregate cache here because:
            // - Incremental updates (add/delete/update) already updated it correctly
            // - Clearing it would force unnecessary full rebuild

        case .aggregates:
            print("🔄 [CacheCoordinator] Invalidating aggregate cache only")
            aggregateCache.clear()

        case .all:
            print("🔄 [CacheCoordinator] Invalidating ALL caches")
            cacheManager.invalidateAll()
            currencyService.invalidate()
            aggregateCache.clear()
        }
    }

    func rebuildAggregates(
        transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository
    ) async {
        print("🔄 [CacheCoordinator] Starting aggregate rebuild (blocking)")
        PerformanceProfiler.start("CacheCoordinator.rebuildAggregates")

        // Clear existing aggregates
        aggregateCache.clear()

        // Rebuild from transactions
        await aggregateCache.rebuildFromTransactions(
            transactions,
            baseCurrency: baseCurrency,
            repository: repository
        )

        // CRITICAL: Invalidate summary cache after rebuild completes
        // This ensures categoryExpenses() fetches fresh data from rebuilt aggregate cache
        await MainActor.run {
            cacheManager.invalidateAll()
            print("🔄 [CacheCoordinator] Summary cache invalidated after rebuild")
        }

        PerformanceProfiler.end("CacheCoordinator.rebuildAggregates")
    }

    func rebuildAggregatesAsync(
        transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository,
        onComplete: @escaping () -> Void
    ) {
        print("🔄 [CacheCoordinator] Starting aggregate rebuild (async)")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            await self.aggregateCache.rebuildFromTransactions(
                transactions,
                baseCurrency: baseCurrency,
                repository: repository
            )

            // CRITICAL: Invalidate summary cache after rebuild completes
            await MainActor.run { [weak self] in
                self?.cacheManager.invalidateAll()
                print("🔄 [CacheCoordinator] Summary cache invalidated after async rebuild")
                onComplete()
            }
        }
    }

    func precomputeCurrencyConversions(
        transactions: [Transaction],
        baseCurrency: String
    ) {
        currencyService.precompute(transactions: transactions, baseCurrency: baseCurrency)
    }
}
