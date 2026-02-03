//
//  CategoryAggregateCacheProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//
//  Protocol for category aggregate cache implementations
//  Allows switching between CategoryAggregateCache and CategoryAggregateCacheOptimized
//

import Foundation

/// Protocol for category aggregate cache
/// Provides unified interface for aggregate caching with different implementations
@MainActor
protocol CategoryAggregateCacheProtocol: AnyObject {

    // MARK: - Properties

    /// Number of cached aggregates
    var cacheCount: Int { get }

    /// Whether cache has been loaded from storage
    var isLoaded: Bool { get }

    // MARK: - Loading

    /// Load aggregates from CoreData
    /// - Parameter repository: CoreData repository
    func loadFromCoreData(repository: CoreDataRepository) async

    // MARK: - Category Expenses

    /// Get category expenses for time filter
    /// - Parameters:
    ///   - timeFilter: Time filter to apply
    ///   - baseCurrency: Base currency for conversion
    ///   - validCategoryNames: Optional set of valid category names to filter
    /// - Returns: Dictionary mapping category name to CategoryExpense
    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?
    ) -> [String: CategoryExpense]

    /// Get daily aggregates for date range
    /// - Parameters:
    ///   - dateRange: Start and end dates
    ///   - baseCurrency: Base currency for conversion
    ///   - validCategoryNames: Optional set of valid category names to filter
    /// - Returns: Dictionary mapping category name to CategoryExpense
    func getDailyAggregates(
        dateRange: (start: Date, end: Date),
        baseCurrency: String,
        validCategoryNames: Set<String>?
    ) -> [String: CategoryExpense]

    // MARK: - Incremental Updates

    /// Update cache for a single transaction (add/remove/update)
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - operation: Operation type (.add, .delete, .update)
    ///   - baseCurrency: Base currency for conversion
    func updateForTransaction(
        transaction: Transaction,
        operation: AggregateOperation,
        baseCurrency: String
    )

    /// Invalidate cache entries for specific categories
    /// - Parameter categoryNames: Set of category names to invalidate
    func invalidateCategories(_ categoryNames: Set<String>)

    // MARK: - Full Rebuild

    /// Rebuild entire cache from transactions
    /// - Parameters:
    ///   - transactions: All transactions to aggregate
    ///   - baseCurrency: Base currency for conversion
    ///   - repository: Repository to save aggregates
    func rebuildFromTransactions(
        _ transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository
    ) async

    /// Clear all cached data
    func clear()
}

// MARK: - Aggregate Operation

/// Aggregate operation type for cache updates
enum AggregateOperation {
    case add
    case delete
    case update(oldTransaction: Transaction)
}
