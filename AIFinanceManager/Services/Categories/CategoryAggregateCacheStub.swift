//
//  CategoryAggregateCacheStub.swift
//  AIFinanceManager
//
//  Phase 8: Minimal stub for CategoryAggregateCacheProtocol
//  Aggregate caching now handled by TransactionStore
//  This provides backward compatibility for TransactionQueryService
//

import Foundation

/// Minimal stub for backward compatibility
/// Phase 8: Aggregate caching moved to TransactionStore
@MainActor
class CategoryAggregateCacheStub: CategoryAggregateCacheProtocol {

    var cacheCount: Int { 0 }
    var isLoaded: Bool { false }

    func loadFromCoreData(repository: CoreDataRepository) async {
        // Phase 8: No-op - TransactionStore handles this
    }

    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?
    ) -> [String: CategoryExpense] {
        // Phase 8: Return empty - query service will fall back to transaction calculation
        return [:]
    }

    func getDailyAggregates(
        dateRange: (start: Date, end: Date),
        baseCurrency: String,
        validCategoryNames: Set<String>?
    ) -> [String: CategoryExpense] {
        // Phase 8: Return empty - query service will fall back to transaction calculation
        return [:]
    }

    func updateForTransaction(
        transaction: Transaction,
        operation: AggregateOperation,
        baseCurrency: String
    ) {
        // Phase 8: No-op - TransactionStore handles this
    }

    func invalidateCategories(_ categoryNames: Set<String>) {
        // Phase 8: No-op - TransactionStore handles this
    }

    func rebuildFromTransactions(
        _ transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository
    ) async {
        // Phase 8: No-op - TransactionStore handles this
    }

    func clear() {
        // Phase 8: No-op - TransactionStore handles this
    }
}
