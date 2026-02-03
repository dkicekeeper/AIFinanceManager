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
    private let aggregateCache: CategoryAggregateCacheProtocol

    // MARK: - Initialization

    init(
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        aggregateCache: CategoryAggregateCacheProtocol
    ) {
        self.cacheManager = cacheManager
        self.currencyService = currencyService
        self.aggregateCache = aggregateCache
    }

    // MARK: - CacheCoordinatorProtocol Implementation

    func invalidate(scope: CacheInvalidationScope) {
        switch scope {
        case .summaryAndCurrency:
            // ✅ FIX: Invalidate summary only, NOT category expenses
            // Category expenses are now cached per-filter and should only be
            // invalidated when transactions change, not when filter changes
            cacheManager.summaryCacheInvalidated = true
            cacheManager.categoryListsCacheInvalidated = true
            currencyService.invalidate()
            // NOTE: We do NOT clear aggregate cache here because:
            // - Incremental updates (add/delete/update) already updated it correctly
            // - Clearing it would force unnecessary full rebuild
            // NOTE: We do NOT clear category expenses cache here because:
            // - It's now cached per-filter (time-based key)
            // - Changing filter should use cached results for that filter
            // - Only transaction changes should invalidate it

        case .aggregates:
            aggregateCache.clear()

        case .all:
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
        PerformanceProfiler.start("CacheCoordinator.rebuildAggregates")

        // ✅ CRITICAL FIX: Invalidate caches BEFORE rebuild to prevent race condition
        // If we invalidate AFTER, Combine publishers can trigger during rebuild and use stale cached data
        cacheManager.summaryCacheInvalidated = true
        cacheManager.categoryListsCacheInvalidated = true
        cacheManager.invalidateCategoryExpenses()
        #if DEBUG
        print("🧹 [CacheCoordinator] Invalidated caches BEFORE aggregate rebuild")
        #endif

        // Clear existing aggregates
        aggregateCache.clear()

        // Rebuild from transactions
        await aggregateCache.rebuildFromTransactions(
            transactions,
            baseCurrency: baseCurrency,
            repository: repository
        )

        #if DEBUG
        print("✅ [CacheCoordinator] Aggregate rebuild complete")
        #endif

        PerformanceProfiler.end("CacheCoordinator.rebuildAggregates")
    }

    func rebuildAggregatesAsync(
        transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository,
        onComplete: @escaping () -> Void
    ) {

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // ✅ CRITICAL FIX: Invalidate caches BEFORE rebuild to prevent race condition
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.cacheManager.summaryCacheInvalidated = true
                self.cacheManager.categoryListsCacheInvalidated = true
                self.cacheManager.invalidateCategoryExpenses()
                #if DEBUG
                print("🧹 [CacheCoordinator] Invalidated caches BEFORE async aggregate rebuild")
                #endif
            }

            await self.aggregateCache.rebuildFromTransactions(
                transactions,
                baseCurrency: baseCurrency,
                repository: repository
            )

            #if DEBUG
            await MainActor.run {
                print("✅ [CacheCoordinator] Async aggregate rebuild complete")
            }
            #endif

            await MainActor.run {
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
