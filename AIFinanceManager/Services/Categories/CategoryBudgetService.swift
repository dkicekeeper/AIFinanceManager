//
//  CategoryBudgetService.swift
//  AIFinanceManager
//
//  Service for category budget calculations and progress tracking.
//  Extracted from CategoriesViewModel for better separation of concerns.
//
//  Phase 22: Added BudgetSpendingCacheService fast path for O(1) reads.
//

import Foundation

/// Service responsible for budget calculations and period management.
struct CategoryBudgetService {

    // MARK: - Dependencies

    let currencyService: TransactionCurrencyService?
    let appSettings: AppSettings?

    /// Phase 22: Optional budget spending cache for O(1) period-total reads.
    var budgetCache: BudgetSpendingCacheService?

    // MARK: - Initialization

    init(
        currencyService: TransactionCurrencyService? = nil,
        appSettings: AppSettings? = nil,
        budgetCache: BudgetSpendingCacheService? = nil
    ) {
        self.currencyService = currencyService
        self.appSettings = appSettings
        self.budgetCache = budgetCache
    }

    // MARK: - Public Methods

    /// Calculate budget progress for a category.
    /// - Parameters:
    ///   - category: The category to calculate progress for
    ///   - transactions: All transactions to analyze (used as fallback)
    /// - Returns: BudgetProgress if category has budget, nil otherwise
    func budgetProgress(for category: CustomCategory, transactions: [Transaction]) -> BudgetProgress? {
        // Only expense categories can have budgets
        guard let budgetAmount = category.budgetAmount,
              category.type == .expense else { return nil }

        // Calculate spent amount for current period
        let spent = calculateSpent(for: category, transactions: transactions)

        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    /// Calculate spent amount for a category in the current budget period.
    ///
    /// Phase 22 fast path: reads from BudgetSpendingCacheService (O(1) CoreData field read).
    /// Falls back to O(N) transaction scan if cache is unavailable (first launch / cache miss).
    func calculateSpent(for category: CustomCategory, transactions: [Transaction]) -> Double {
        let baseCurrency = appSettings?.baseCurrency ?? "KZT"

        // Phase 22: Fast path — read from persistent cache in CustomCategoryEntity
        if let cached = budgetCache?.cachedSpent(for: category.name, currency: baseCurrency) {
            return cached
        }

        // Slow path: O(N) scan (first launch or cache not yet populated)
        return calculateSpentSlow(for: category, transactions: transactions)
    }

    /// Original O(N) scan implementation, used as fallback when cache is unavailable.
    func calculateSpentSlow(for category: CustomCategory, transactions: [Transaction]) -> Double {
        let periodStart = budgetPeriodStart(for: category)
        let periodEnd = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return transactions
            .filter { transaction in
                guard transaction.category == category.name,
                      transaction.type == .expense,
                      let transactionDate = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return transactionDate >= periodStart && transactionDate <= periodEnd
            }
            .reduce(0) { sum, transaction in
                // Convert to base currency if possible
                if let currencyService = currencyService, let appSettings = appSettings {
                    let amountInBaseCurrency = currencyService.getConvertedAmountOrCompute(
                        transaction: transaction,
                        to: appSettings.baseCurrency
                    )
                    return sum + amountInBaseCurrency
                } else {
                    // Fallback: use amount without conversion
                    return sum + transaction.amount
                }
            }
    }

    /// Calculate budget period start date for a category.
    /// - Parameter category: The category to calculate period start for
    /// - Returns: Start date of current budget period
    func budgetPeriodStart(for category: CustomCategory) -> Date {
        guard category.budgetStartDate != nil else { return Date() }

        let calendar = Calendar.current
        let now = Date()

        switch category.budgetPeriod {
        case .weekly:
            // Start of current week
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        case .monthly:
            // Reset on specific day of month
            let components = calendar.dateComponents([.year, .month], from: now)
            var startComponents = components
            startComponents.day = category.budgetResetDay

            if let resetDate = calendar.date(from: startComponents) {
                // If reset day hasn't happened this month yet, use previous month
                if resetDate > now {
                    return calendar.date(byAdding: .month, value: -1, to: resetDate) ?? resetDate
                }
                return resetDate
            }
            return now

        case .yearly:
            // Start of current year
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
    }

}

// MARK: - Static Helpers

extension CategoryBudgetService {

    /// Create budget service with all dependencies (Phase 22: includes BudgetSpendingCacheService).
    static func create(
        currencyService: TransactionCurrencyService,
        appSettings: AppSettings,
        budgetCache: BudgetSpendingCacheService? = nil
    ) -> CategoryBudgetService {
        CategoryBudgetService(
            currencyService: currencyService,
            appSettings: appSettings,
            budgetCache: budgetCache
        )
    }
}
