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
        print("💰 [TransactionQueryService] Called - cacheInvalidated: \(cacheManager.summaryCacheInvalidated)")

        // Return cached summary if valid
        if !cacheManager.summaryCacheInvalidated, let cached = cacheManager.cachedSummary {
            print("💰 [TransactionQueryService] Returning cached: income=\(cached.totalIncome), expense=\(cached.totalExpenses)")
            return cached
        }

        print("💰 [TransactionQueryService] Recalculating summary...")
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

        print("💰 [TransactionQueryService] Calculated: income=\(totalIncome), expense=\(totalExpenses), netFlow=\(totalIncome - totalExpenses)")

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
        print("📊 [TransactionQueryService] Called - cacheInvalidated: \(cacheManager.categoryExpensesCacheInvalidated)")

        // Check cache
        if !cacheManager.categoryExpensesCacheInvalidated,
           let cached = cacheManager.cachedCategoryExpenses {
            print("📊 [TransactionQueryService] Returning cached data: \(cached.keys.count) categories")
            return cached
        }

        print("📊 [TransactionQueryService] Recalculating from aggregate cache...")

        // Use aggregate cache for efficient calculation
        let result = aggregateCache.getCategoryExpenses(
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            validCategoryNames: validCategoryNames
        )

        print("📊 [TransactionQueryService] Fresh data calculated: \(result.keys.count) categories, total: \(result.values.reduce(0) { $0 + $1.total })")

        cacheManager.cachedCategoryExpenses = result
        cacheManager.categoryExpensesCacheInvalidated = false

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
