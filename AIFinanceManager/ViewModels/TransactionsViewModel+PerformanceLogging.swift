//
//  TransactionsViewModel+PerformanceLogging.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Расширение для добавления детального логирования производительности в TransactionsViewModel
//

import Foundation

// MARK: - Performance Logging Extension

extension TransactionsViewModel {

    /// Логировать фильтрацию транзакций с детальными метриками
    func logFilterTransactionsForHistory(
        inputCount: Int,
        outputCount: Int,
        timeFilter: String,
        hasAccountFilter: Bool,
        hasSearchText: Bool,
        hasCategoryFilter: Bool
    ) {
        #if DEBUG
        let metadata: [String: Any] = [
            "inputCount": inputCount,
            "outputCount": outputCount,
            "reductionPercent": inputCount > 0 ? Int((1.0 - Double(outputCount) / Double(inputCount)) * 100) : 0,
            "timeFilter": timeFilter,
            "hasAccountFilter": hasAccountFilter,
            "hasSearchText": hasSearchText,
            "hasCategoryFilter": hasCategoryFilter
        ]

        print("📊 [FilterTransactions] Filtered \(inputCount) → \(outputCount) transactions")
        print("   Filters: time=\(timeFilter), account=\(hasAccountFilter), search=\(hasSearchText), category=\(hasCategoryFilter)")

        if outputCount == 0 && inputCount > 0 {
            print("   ⚠️ WARNING: All transactions filtered out!")
        }
        #endif
    }

    /// Логировать группировку транзакций
    func logGroupTransactions(
        transactionCount: Int,
        sectionCount: Int,
        avgPerSection: Double
    ) {
        #if DEBUG
        print("📊 [GroupTransactions] Grouped \(transactionCount) transactions into \(sectionCount) sections")
        print("   Average per section: \(String(format: "%.1f", avgPerSection))")

        if sectionCount > 100 {
            print("   ⚠️ WARNING: High section count (\(sectionCount)) may impact performance!")
        }
        #endif
    }

    /// Логировать поиск по подкатегориям
    func logSubcategoryLookup(
        transactionId: String,
        foundCount: Int,
        cacheHit: Bool
    ) {
        #if DEBUG
        let cacheStatus = cacheHit ? "CACHE HIT" : "CACHE MISS"
        print("🔍 [SubcategoryLookup] Transaction \(transactionId): found \(foundCount) subcategories [\(cacheStatus)]")
        #endif
    }

    /// Логировать парсинг дат
    func logDateParsing(
        transactionId: String,
        dateString: String,
        cacheHit: Bool,
        parsedSuccessfully: Bool
    ) {
        #if DEBUG
        if !parsedSuccessfully {
            print("⚠️ [DateParsing] Failed to parse date '\(dateString)' for transaction \(transactionId)")
        }

        if !cacheHit && parsedSuccessfully {
            print("🔍 [DateParsing] Date '\(dateString)' parsed and cached")
        }
        #endif
    }
}

// MARK: - Category Filtering Performance

extension TransactionsViewModel {

    /// Анализировать производительность фильтрации по категориям
    func analyzeCategoryFilterPerformance() {
        #if DEBUG
        guard let selectedCategories = selectedCategories else {
            print("📊 [CategoryFilter] No category filter active")
            return
        }

        let categoryTransactions = allTransactions.filter { transaction in
            selectedCategories.contains(transaction.category)
        }

        let reductionPercent = allTransactions.count > 0 ?
            Int((1.0 - Double(categoryTransactions.count) / Double(allTransactions.count)) * 100) : 0

        print("📊 [CategoryFilter] Filtering by \(selectedCategories.count) categories")
        print("   Input: \(allTransactions.count) transactions")
        print("   Output: \(categoryTransactions.count) transactions")
        print("   Reduction: \(reductionPercent)%")

        // Анализ распределения по категориям
        var categoryDistribution: [String: Int] = [:]
        for transaction in categoryTransactions {
            categoryDistribution[transaction.category, default: 0] += 1
        }

        print("   Category distribution:")
        for (category, count) in categoryDistribution.sorted(by: { $0.value > $1.value }) {
            print("     - \(category): \(count) transactions")
        }
        #endif
    }
}

// MARK: - Account Filtering Performance

extension TransactionsViewModel {

    /// Анализировать производительность фильтрации по счету
    func analyzeAccountFilterPerformance(accountId: String?) {
        #if DEBUG
        guard let accountId = accountId else {
            print("📊 [AccountFilter] No account filter active")
            return
        }

        guard let account = accounts.first(where: { $0.id == accountId }) else {
            print("⚠️ [AccountFilter] Account \(accountId) not found!")
            return
        }

        let accountTransactions = allTransactions.filter { transaction in
            transaction.accountId == accountId || transaction.targetAccountId == accountId
        }

        let reductionPercent = allTransactions.count > 0 ?
            Int((1.0 - Double(accountTransactions.count) / Double(allTransactions.count)) * 100) : 0

        print("📊 [AccountFilter] Filtering by account '\(account.name)'")
        print("   Input: \(allTransactions.count) transactions")
        print("   Output: \(accountTransactions.count) transactions")
        print("   Reduction: \(reductionPercent)%")
        #endif
    }
}

// MARK: - Search Performance

extension TransactionsViewModel {

    /// Анализировать производительность поиска
    func analyzeSearchPerformance(searchText: String, results: [Transaction]) {
        #if DEBUG
        guard !searchText.isEmpty else {
            print("📊 [SearchFilter] No search text")
            return
        }

        let reductionPercent = allTransactions.count > 0 ?
            Int((1.0 - Double(results.count) / Double(allTransactions.count)) * 100) : 0

        print("📊 [SearchFilter] Searching for '\(searchText)'")
        print("   Input: \(allTransactions.count) transactions")
        print("   Output: \(results.count) transactions")
        print("   Reduction: \(reductionPercent)%")

        if results.isEmpty {
            print("   ⚠️ WARNING: No results found for search text '\(searchText)'")
        }

        // Анализ совпадений по полям
        var matchFields: [String: Int] = [:]
        for transaction in results {
            if transaction.category.lowercased().contains(searchText.lowercased()) {
                matchFields["category", default: 0] += 1
            }
            if transaction.description.lowercased().contains(searchText.lowercased()) {
                matchFields["description", default: 0] += 1
            }
            if String(format: "%.2f", transaction.amount).contains(searchText) {
                matchFields["amount", default: 0] += 1
            }
        }

        if !matchFields.isEmpty {
            print("   Match distribution:")
            for (field, count) in matchFields.sorted(by: { $0.value > $1.value }) {
                print("     - \(field): \(count) matches")
            }
        }
        #endif
    }
}
