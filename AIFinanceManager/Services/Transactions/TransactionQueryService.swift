//
//  TransactionQueryService.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Service for read-only transaction queries
/// Extracted from TransactionsViewModel (lines 553-715) to follow SRP
@MainActor
class TransactionQueryService: TransactionQueryServiceProtocol {

    // MARK: - Dependencies

    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }

    // MARK: - TransactionQueryServiceProtocol Implementation

    func calculateSummary(
        transactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> Summary {

        // Return cached summary if valid
        if !cacheManager.summaryCacheInvalidated, let cached = cacheManager.cachedSummary {
            return cached
        }

        PerformanceProfiler.start("TransactionQueryService.calculateSummary")

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter

        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0

        for transaction in transactions {
            // Use cached conversion if available
            let amountInBaseCurrency = currencyService.getConvertedAmountOrCompute(
                transaction: transaction,
                to: baseCurrency
            )

            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                continue
            }

            let isFutureDate = transactionDate > today

            if !isFutureDate {
                switch transaction.type {
                case .income:
                    totalIncome += amountInBaseCurrency
                case .expense:
                    totalExpenses += amountInBaseCurrency
                case .internalTransfer:
                    totalInternal += amountInBaseCurrency
                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    break
                }
            }
        }

        let dates = transactions.map { $0.date }.sorted()

        let result = Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            plannedAmount: 0  // Skip planned amount for performance
        )


        cacheManager.cachedSummary = result
        cacheManager.summaryCacheInvalidated = false

        PerformanceProfiler.end("TransactionQueryService.calculateSummary")
        return result
    }

    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?,
        aggregateCache: CategoryAggregateCache,
        cacheManager: TransactionCacheManager
    ) -> [String: CategoryExpense] {

        // ✅ Check cache with time filter as key
        if let cached = cacheManager.getCachedCategoryExpenses(for: timeFilter) {
            return cached
        }

        // Use aggregate cache for efficient calculation
        let result = aggregateCache.getCategoryExpenses(
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            validCategoryNames: validCategoryNames
        )

        // ✅ CRITICAL FIX: Only cache non-empty results
        // During aggregate cache rebuild, getCategoryExpenses() may return empty results
        // If we cache empty results, UI will show 0.00 even after rebuild completes
        // Empty results should trigger a fresh calculation next time
        if !result.isEmpty {
            cacheManager.setCachedCategoryExpenses(result, for: timeFilter)
        } else {
            #if DEBUG
            print("⚠️ [TransactionQueryService] NOT caching empty result - aggregate cache may still be rebuilding")
            #endif
        }

        return result
    }

    func getPopularCategories(
        expenses: [String: CategoryExpense]
    ) -> [String] {
        return Array(expenses.keys)
            .sorted { expenses[$0]?.total ?? 0 > expenses[$1]?.total ?? 0 }
    }

    func getUniqueCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedUniqueCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }

        let result = Array(categories).sorted()
        cacheManager.cachedUniqueCategories = result
        return result
    }

    func getExpenseCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedExpenseCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions where transaction.type == .expense {
            let categoryName = transaction.category.isEmpty
                ? String(localized: "category.uncategorized")
                : transaction.category
            categories.insert(categoryName)
        }

        let result = Array(categories).sorted()
        cacheManager.cachedExpenseCategories = result
        return result
    }

    func getIncomeCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedIncomeCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions where transaction.type == .income {
            let categoryName = transaction.category.isEmpty
                ? String(localized: "category.uncategorized")
                : transaction.category
            categories.insert(categoryName)
        }

        let result = Array(categories).sorted()
        cacheManager.cachedIncomeCategories = result
        return result
    }
}
