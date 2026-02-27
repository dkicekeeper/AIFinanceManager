//
//  CategoryDisplayDataMapper.swift
//  AIFinanceManager
//
//  Maps categories to display data with totals and budget information.
//  Extracted from QuickAddTransactionView to follow Single Responsibility Principle.
//

import Foundation
import SwiftUI

@MainActor
final class CategoryDisplayDataMapper: CategoryDisplayDataMapperProtocol {

    // MARK: - Memoization Cache

    /// ✅ OPTIMIZATION: Cache key for memoization
    private struct CacheKey: Hashable {
        let categoriesHash: Int
        let expensesHash: Int
        let type: TransactionType
        let baseCurrency: String

        init(customCategories: [CustomCategory], categoryExpenses: [String: CategoryExpense], type: TransactionType, baseCurrency: String) {
            // Create stable hash from categories (ID + order + budgetAmount)
            self.categoriesHash = customCategories
                .map { "\($0.id)_\($0.order ?? 0)_\(String(format: "%.2f", $0.budgetAmount ?? 0))" }
                .sorted()
                .joined()
                .hashValue

            // Create stable hash from expenses (category:total pairs, sorted)
            self.expensesHash = categoryExpenses
                .map { "\($0.key):\(String(format: "%.2f", $0.value.total))" }
                .sorted()
                .joined()
                .hashValue

            self.type = type
            self.baseCurrency = baseCurrency
        }
    }

    /// ✅ OPTIMIZATION: Cached result to avoid redundant mapping
    private var cache: (key: CacheKey, result: [CategoryDisplayData])?

    // MARK: - Public Methods

    func mapCategories(
        customCategories: [CustomCategory],
        categoryExpenses: [String: CategoryExpense],
        type: TransactionType,
        baseCurrency: String
    ) -> [CategoryDisplayData] {
        // ✅ OPTIMIZATION: Check cache first
        let cacheKey = CacheKey(
            customCategories: customCategories,
            categoryExpenses: categoryExpenses,
            type: type,
            baseCurrency: baseCurrency
        )

        if let cached = cache, cached.key == cacheKey {
            return cached.result
        }

        // Filter categories by type
        let filteredCategories = customCategories.filter { $0.type == type }

        // Create Set of existing category names for validation
        let existingCategoryNames = Set(filteredCategories.map { $0.name })

        // Collect all unique categories from custom categories and expenses
        var allCategories = Set<String>()

        // Add custom categories
        for category in filteredCategories {
            allCategories.insert(category.name)
        }

        // Add categories from expenses (only if they exist in custom categories)
        for categoryName in categoryExpenses.keys {
            if existingCategoryNames.contains(categoryName) {
                allCategories.insert(categoryName)
            }
        }

        // Map to display data
        let displayData = allCategories.compactMap { categoryName -> CategoryDisplayData? in
            mapCategory(
                name: categoryName,
                customCategories: filteredCategories,
                categoryExpenses: categoryExpenses,
                type: type,
                baseCurrency: baseCurrency
            )
        }

        // Create a lookup for category order
        let orderLookup = Dictionary(uniqueKeysWithValues: filteredCategories.compactMap { category -> (String, Int)? in
            guard let order = category.order else { return nil }
            return (category.name, order)
        })

        // Sort by custom order if available, otherwise by name
        let result = displayData.sorted { category1, category2 in
            let order1 = orderLookup[category1.name]
            let order2 = orderLookup[category2.name]

            // If both have custom order, sort by order
            if let o1 = order1, let o2 = order2 {
                return o1 < o2
            }
            // If only one has custom order, it goes first
            if order1 != nil {
                return true
            }
            if order2 != nil {
                return false
            }
            // If neither has custom order, sort by name
            return category1.name < category2.name
        }

        // ✅ OPTIMIZATION: Cache the result
        cache = (cacheKey, result)

        return result
    }

    // MARK: - Private Methods

    private func mapCategory(
        name: String,
        customCategories: [CustomCategory],
        categoryExpenses: [String: CategoryExpense],
        type: TransactionType,
        baseCurrency: String
    ) -> CategoryDisplayData? {
        // Find custom category
        let customCategory = customCategories.first {
            $0.name.lowercased() == name.lowercased() && $0.type == type
        }

        // Get total from expenses
        let total = categoryExpenses[name]?.total ?? 0

        // Get budget progress (pre-calculated)
        let budgetProgress = customCategory.flatMap { category -> BudgetProgress? in
            guard let budgetAmount = category.budgetAmount, budgetAmount > 0 else { return nil }
            return BudgetProgress(budgetAmount: budgetAmount, spent: total)
        }

        // ✅ CATEGORY REFACTORING: Use cached style data
        let styleData = CategoryStyleHelper.cached(
            category: name,
            type: type,
            customCategories: customCategories
        )

        return CategoryDisplayData(
            id: customCategory?.id ?? UUID().uuidString,
            name: name,
            type: type,
            iconName: styleData.iconName,
            iconColor: styleData.iconColor,
            total: total,
            budgetAmount: customCategory?.budgetAmount,
            budgetProgress: budgetProgress
        )
    }
}
