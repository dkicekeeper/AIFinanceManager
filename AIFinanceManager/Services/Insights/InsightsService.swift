//
//  InsightsService.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Core analytics engine that composes existing services to generate smart insights.
//
//  Performance notes:
//  - Static DateFormatters avoid allocations inside loops
//  - calculateSummary is called once per scope; results are reused
//  - resolveAmount delegates to convertedAmount (already cached by TransactionCurrencyService)
//

import Foundation
import SwiftUI
import os

@MainActor
final class InsightsService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsService")
    // MARK: - Dependencies

    private let transactionStore: TransactionStore
    private let filterService: TransactionFilterService
    private let queryService: TransactionQueryService
    private let budgetService: CategoryBudgetService
    private let cache: InsightsCache

    // MARK: - Static formatters (avoid per-call allocation)

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.locale = .current
        return f
    }()

    private static let monthAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = .current
        return f
    }()

    private static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    // MARK: - Init

    init(
        transactionStore: TransactionStore,
        filterService: TransactionFilterService,
        queryService: TransactionQueryService,
        budgetService: CategoryBudgetService,
        cache: InsightsCache
    ) {
        self.transactionStore = transactionStore
        self.filterService = filterService
        self.queryService = queryService
        self.budgetService = budgetService
        self.cache = cache
    }

    // MARK: - Public API

    func generateAllInsights(
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        let cacheKey = InsightsCache.makeKey(timeFilter: timeFilter, baseCurrency: baseCurrency)
        if let cached = cache.get(key: cacheKey) {
            Self.logger.debug("⚡️ [Insights] Cache HIT — key=\(cacheKey, privacy: .public), count=\(cached.count)")
            return cached
        }

        let allTransactions = Array(transactionStore.transactions)
        let range = timeFilter.dateRange()
        let filtered = filterService.filterByTimeRange(allTransactions, start: range.start, end: range.end)

        Self.logger.debug("📊 [Insights] Generate START — filter=\(timeFilter.displayName, privacy: .public), currency=\(baseCurrency, privacy: .public), all=\(allTransactions.count), filtered=\(filtered.count)")
        PerformanceLogger.InsightsMetrics.logGenerateStart(filteredCount: filtered.count, cacheHit: false)

        // Single summary calculation for the filtered period — reused by spending + income sections.
        // IMPORTANT: We bypass queryService.calculateSummary here because it uses a global
        // TransactionCacheManager cache (cacheManager.cachedSummary) that is NOT invalidated
        // when the user switches time filters. This causes cross-filter contamination: switching
        // from "This Month" to "Last Month" would return February's partial data for the January
        // period summary. calculateMonthlySummary computes directly from the transaction slice.
        let (periodIncome, periodExpenses) = calculateMonthlySummary(
            transactions: filtered,
            baseCurrency: baseCurrency,
            currencyService: currencyService
        )
        let periodNetFlow = periodIncome - periodExpenses
        // Wrap into a local value type so downstream code keeps using .totalIncome / .totalExpenses syntax
        let periodSummary = PeriodSummary(totalIncome: periodIncome, totalExpenses: periodExpenses, netFlow: periodNetFlow)
        Self.logger.debug("💰 [Insights] Period summary — income=\(String(format: "%.0f", periodSummary.totalIncome), privacy: .public) \(baseCurrency, privacy: .public), expenses=\(String(format: "%.0f", periodSummary.totalExpenses), privacy: .public) \(baseCurrency, privacy: .public), net=\(String(format: "%.0f", periodSummary.netFlow), privacy: .public) \(baseCurrency, privacy: .public)")

        var insights: [Insight] = []

        insights.append(contentsOf: generateSpendingInsights(
            filtered: filtered,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateIncomeInsights(
            filtered: filtered,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: filtered,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency
        ))

        insights.append(contentsOf: generateRecurringInsights(baseCurrency: baseCurrency))

        insights.append(contentsOf: generateCashFlowInsights(
            allTransactions: allTransactions,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            balanceFor: balanceFor
        ))

        Self.logger.debug("✅ [Insights] Generate END — total insights=\(insights.count) (spending=\(insights.filter { $0.category == .spending }.count), income=\(insights.filter { $0.category == .income }.count), budget=\(insights.filter { $0.category == .budget }.count), recurring=\(insights.filter { $0.category == .recurring }.count), cashFlow=\(insights.filter { $0.category == .cashFlow }.count))")
        PerformanceLogger.InsightsMetrics.logGenerateEnd(total: insights.count)

        cache.set(key: cacheKey, insights: insights)
        return insights
    }

    func invalidateCache() {
        cache.invalidateAll()
    }

    // MARK: - Monthly Data Points (shared utility)

    func computeMonthlyDataPoints(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,  // kept for API compatibility; not used inside (see calculateMonthlySummary)
        currencyService: TransactionCurrencyService,
        anchorDate: Date? = nil
    ) -> [MonthlyDataPoint] {
        PerformanceLogger.InsightsMetrics.logMonthlyPointStart(months: months, transactionCount: transactions.count)
        Self.logger.debug("📅 [Insights] Monthly points START — months=\(months), transactions=\(transactions.count)")

        let calendar = Calendar.current
        // Bug 1 fix: anchor to the provided date (e.g. end of timeFilter range) so that
        // historical filters (Last Year, Last 3 Months, etc.) produce month points relative
        // to their period end, not relative to today.
        let anchor = anchorDate ?? Date()
        var dataPoints: [MonthlyDataPoint] = []
        dataPoints.reserveCapacity(months)

        for i in (0..<months).reversed() {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -i, to: startOfMonth(calendar, for: anchor)),
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            let monthTransactions = filterService.filterByTimeRange(transactions, start: monthStart, end: monthEnd)
            // Use cache-bypassing helper — see calculateMonthlySummary for root cause explanation.
            let (monthIncome, monthExpenses) = calculateMonthlySummary(
                transactions: monthTransactions,
                baseCurrency: baseCurrency,
                currencyService: currencyService
            )
            let monthNetFlow = monthIncome - monthExpenses

            let label = Self.monthYearFormatter.string(from: monthStart)
            Self.logger.debug("   📅 \(label, privacy: .public) — txn=\(monthTransactions.count), income=\(String(format: "%.0f", monthIncome), privacy: .public), exp=\(String(format: "%.0f", monthExpenses), privacy: .public), net=\(String(format: "%.0f", monthNetFlow), privacy: .public)")

            dataPoints.append(MonthlyDataPoint(
                id: Self.yearMonthFormatter.string(from: monthStart),
                month: monthStart,
                income: monthIncome,
                expenses: monthExpenses,
                netFlow: monthNetFlow,
                label: label
            ))
        }

        PerformanceLogger.InsightsMetrics.logMonthlyPointEnd(pointCount: dataPoints.count)
        Self.logger.debug("📅 [Insights] Monthly points END — \(dataPoints.count) points computed")
        return dataPoints
    }

    // MARK: - Spending Insights

    // MARK: - MoM Reference Date Helper

    /// Returns the reference date for month-over-month comparisons.
    /// For current/rolling filters (e.g. "This Month", "Last 30 Days") this is today,
    /// so "this month" = the current calendar month.
    /// For historical filters (e.g. "Last Year", "Last 3 Months") this is the filter's
    /// INCLUSIVE last day (end - 1 second), because `timeFilter.dateRange().end` is
    /// EXCLUSIVE (e.g. "Last Month" Jan 2026 → end = Feb 1 2026 00:00:00).
    /// Without this correction, startOfMonth(Feb 1) = Feb 2026, so "this month" becomes
    /// February, which has 0 transactions in the period, making MoM always show 0.
    private func momReferenceDate(for timeFilter: TimeFilter) -> Date {
        let end = timeFilter.dateRange().end
        // If the filter ends within the current day (or in the future), use actual now.
        if Calendar.current.isDateInToday(end) || end > Date() {
            return Date()
        }
        // Historical preset: subtract 1 second to convert exclusive end → inclusive last instant
        // e.g. Feb 1 00:00:00 → Jan 31 23:59:59 → startOfMonth = Jan 1 ✓
        return Calendar.current.date(byAdding: .second, value: -1, to: end) ?? end
    }

    private func generateSpendingInsights(
        filtered: [Transaction],
        allTransactions: [Transaction],
        periodSummary: PeriodSummary,
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> [Insight] {
        var insights: [Insight] = []
        let expenses = filterService.filterByType(filtered, type: .expense)
        guard !expenses.isEmpty else {
            Self.logger.debug("🛒 [Insights] Spending — SKIPPED (no expenses in period)")
            return insights
        }

        // 1. Top spending category
        let categoryGroups = Dictionary(grouping: expenses, by: { $0.category })
        let sortedCategories: [(key: String, total: Double)] = categoryGroups
            .map { key, txns in
                let total = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                return (key: key, total: total)
            }
            .sorted { $0.total > $1.total }

        let topCategoryName = sortedCategories.first?.key ?? "—"
        let topCategoryAmount = sortedCategories.first?.total ?? 0
        PerformanceLogger.InsightsMetrics.logSpendingStart(expenseCount: expenses.count, categoryCount: categoryGroups.count)
        Self.logger.debug("🛒 [Insights] Spending — expenses=\(expenses.count), categories=\(categoryGroups.count), top='\(topCategoryName, privacy: .public)' (\(String(format: "%.0f", topCategoryAmount), privacy: .public) \(baseCurrency, privacy: .public))")
        for cat in sortedCategories.prefix(5) {
            let pct = periodSummary.totalExpenses > 0 ? (cat.total / periodSummary.totalExpenses) * 100 : 0
            Self.logger.debug("   🛒 \(cat.key, privacy: .public): \(String(format: "%.0f", cat.total), privacy: .public) (\(String(format: "%.1f%%", pct), privacy: .public))")
        }

        if let top = sortedCategories.first {
            let percentage = periodSummary.totalExpenses > 0
                ? (top.total / periodSummary.totalExpenses) * 100
                : 0

            // Bug 2 fix: build subcategory breakdown only for top 5 categories.
            // Building it for all 18+ categories was the main source of 422ms lag
            // (subcategory grouping + sorting runs per category).
            let breakdownItems: [CategoryBreakdownItem] = sortedCategories.prefix(5).map { item in
                let pct = periodSummary.totalExpenses > 0 ? (item.total / periodSummary.totalExpenses) * 100 : 0
                let cat = transactionStore.categories.first { $0.name == item.key }
                let catColor = cat.map { Color(hex: $0.colorHex) } ?? AppColors.accent
                let txns = categoryGroups[item.key] ?? []

                let subcategoryTotals = Dictionary(grouping: txns, by: { $0.subcategory ?? "" })
                    .compactMap { subKey, subTxns -> SubcategoryBreakdownItem? in
                        guard !subKey.isEmpty else { return nil }
                        let subTotal = subTxns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                        return SubcategoryBreakdownItem(
                            id: subKey,
                            name: subKey,
                            amount: subTotal,
                            percentage: item.total > 0 ? (subTotal / item.total) * 100 : 0
                        )
                    }
                    .sorted { $0.amount > $1.amount }

                return CategoryBreakdownItem(
                    id: item.key,
                    categoryName: item.key,
                    amount: item.total,
                    percentage: pct,
                    color: catColor,
                    iconSource: cat?.iconSource,
                    subcategories: subcategoryTotals
                )
            }

            insights.append(Insight(
                id: "top_spending_\(top.key)",
                type: .topSpendingCategory,
                title: String(localized: "insights.topCategory"),
                subtitle: top.key,
                metric: InsightMetric(
                    value: top.total,
                    formattedValue: Formatting.formatCurrencySmart(top.total, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: .down,
                    changePercent: percentage,
                    changeAbsolute: nil,
                    comparisonPeriod: String(format: "%.0f%% %@", percentage, String(localized: "insights.ofTotal"))
                ),
                severity: percentage > 50 ? .warning : .neutral,
                category: .spending,
                detailData: .categoryBreakdown(breakdownItems)
            ))
        }

        // 2. Month-over-month spending change
        // Bug 4 fix: use momReferenceDate instead of Date() so that historical
        // filters (Last Year, etc.) compare the last *complete* month of the
        // filter range against the month before it, rather than comparing
        // the current partial February against January.
        // Cap thisMonthEnd to refDate: for "Last Month" refDate = Jan 31, so we
        // should not pull transactions from Feb 1+ into the "this month" bucket.
        let calendar = Calendar.current
        let refDate = momReferenceDate(for: timeFilter)
        let thisMonthStart = startOfMonth(calendar, for: refDate)
        // Use min(fullMonthEnd, refDate+1day) so historical filters stay within range
        let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
        let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
        let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

        if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
           let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {

            // Performance fix: single pass over allTransactions to build both MoM buckets.
            // Previously this called filterByType (O(n)) then filterByTimeRange (O(n)) twice,
            // scanning 18k transactions 4× total. Now we do it in one O(n) pass.
            var thisMonthTotal: Double = 0
            var prevMonthTotal: Double = 0
            let dateFormatter = DateFormatters.dateFormatter
            for tx in allTransactions where tx.type == .expense {
                guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                if txDate >= thisMonthStart && txDate < thisMonthEnd {
                    thisMonthTotal += amount
                } else if txDate >= prevMonthStart && txDate < prevMonthEnd {
                    prevMonthTotal += amount
                }
            }

            Self.logger.debug("🔄 [Insights] MoM spending — this=\(String(format: "%.0f", thisMonthTotal), privacy: .public), prev=\(String(format: "%.0f", prevMonthTotal), privacy: .public)")

            if prevMonthTotal > 0 {
                let changePercent = ((thisMonthTotal - prevMonthTotal) / prevMonthTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 20 ? .warning : (changePercent < -10 ? .positive : .neutral)

                Self.logger.debug("🔄 [Insights] MoM spending change=\(String(format: "%+.1f%%", changePercent), privacy: .public), direction=\(String(describing: direction), privacy: .public), severity=\(String(describing: severity), privacy: .public)")

                insights.append(Insight(
                    id: "mom_spending",
                    type: .monthOverMonthChange,
                    title: String(localized: "insights.monthOverMonth"),
                    subtitle: String(localized: "insights.vsPreviousPeriod"),
                    metric: InsightMetric(
                        value: thisMonthTotal,
                        formattedValue: Formatting.formatCurrencySmart(thisMonthTotal, currency: baseCurrency),
                        currency: baseCurrency,
                        unit: nil
                    ),
                    trend: InsightTrend(
                        direction: direction,
                        changePercent: changePercent,
                        changeAbsolute: thisMonthTotal - prevMonthTotal,
                        comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
                    ),
                    severity: severity,
                    category: .spending,
                    detailData: nil
                ))
            }
        }

        // 3. Average daily spending (uses already-computed periodSummary)
        let range = timeFilter.dateRange()
        let days = max(1, calendar.dateComponents([.day], from: range.start, to: min(range.end, refDate)).day ?? 1)
        let avgDaily = periodSummary.totalExpenses / Double(days)

        Self.logger.debug("📆 [Insights] Avg daily — totalExpenses=\(String(format: "%.0f", periodSummary.totalExpenses), privacy: .public), days=\(days), avg=\(String(format: "%.0f", avgDaily), privacy: .public) \(baseCurrency, privacy: .public)")

        insights.append(Insight(
            id: "avg_daily",
            type: .averageDailySpending,
            title: String(localized: "insights.avgDailySpending"),
            subtitle: "\(days) " + String(localized: "insights.days"),
            metric: InsightMetric(
                value: avgDaily,
                formattedValue: Formatting.formatCurrencySmart(avgDaily, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .spending,
            detailData: nil
        ))

        PerformanceLogger.InsightsMetrics.logSpendingEnd(
            insightCount: insights.count,
            topCategory: topCategoryName,
            topAmount: topCategoryAmount
        )
        return insights
    }

    // MARK: - Income Insights

    private func generateIncomeInsights(
        filtered: [Transaction],
        allTransactions: [Transaction],
        periodSummary: PeriodSummary,
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> [Insight] {
        var insights: [Insight] = []
        let incomeTransactions = filterService.filterByType(filtered, type: .income)
        guard !incomeTransactions.isEmpty else {
            Self.logger.debug("💵 [Insights] Income — SKIPPED (no income transactions in period)")
            return insights
        }

        PerformanceLogger.InsightsMetrics.logIncomeStart(incomeCount: incomeTransactions.count)
        Self.logger.debug("💵 [Insights] Income START — incomeTransactions=\(incomeTransactions.count)")

        // 1. Income growth (this month vs last month)
        // Bug 4 fix: same anchor as spending MoM — use filter range end for
        // historical filters so comparison isn't skewed by a partial current month.
        // Cap thisMonthEnd to refDate for the same reason as spending MoM.
        let calendar = Calendar.current
        let refDate = momReferenceDate(for: timeFilter)
        let thisMonthStart = startOfMonth(calendar, for: refDate)
        let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
        let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
        let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

        if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
           let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {

            // Performance fix: single pass (same approach as spending MoM above)
            var thisTotal: Double = 0
            var prevTotal: Double = 0
            let dateFormatter = DateFormatters.dateFormatter
            for tx in allTransactions where tx.type == .income {
                guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                if txDate >= thisMonthStart && txDate < thisMonthEnd {
                    thisTotal += amount
                } else if txDate >= prevMonthStart && txDate < prevMonthEnd {
                    prevTotal += amount
                }
            }

            Self.logger.debug("💵 [Insights] Income MoM — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if prevTotal > 0 {
                let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 10 ? .positive : (changePercent < -10 ? .warning : .neutral)

                Self.logger.debug("💵 [Insights] Income growth=\(String(format: "%+.1f%%", changePercent), privacy: .public), severity=\(String(describing: severity), privacy: .public)")

                insights.append(Insight(
                    id: "income_growth",
                    type: .incomeGrowth,
                    title: String(localized: "insights.incomeGrowth"),
                    subtitle: String(localized: "insights.vsPreviousPeriod"),
                    metric: InsightMetric(
                        value: thisTotal,
                        formattedValue: Formatting.formatCurrencySmart(thisTotal, currency: baseCurrency),
                        currency: baseCurrency,
                        unit: nil
                    ),
                    trend: InsightTrend(
                        direction: direction,
                        changePercent: changePercent,
                        changeAbsolute: thisTotal - prevTotal,
                        comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
                    ),
                    severity: severity,
                    category: .income,
                    detailData: nil
                ))
            }
        }

        // 2. Income vs Expense ratio — reuse periodSummary (no extra calculateSummary call)
        if periodSummary.totalExpenses > 0 {
            let ratio = periodSummary.totalIncome / periodSummary.totalExpenses
            let severity: InsightSeverity = ratio >= 1.5 ? .positive : (ratio >= 1.0 ? .neutral : .critical)
            Self.logger.debug("💵 [Insights] I/E ratio=\(String(format: "%.2f", ratio), privacy: .public)x, severity=\(String(describing: severity), privacy: .public)")

            insights.append(Insight(
                id: "income_vs_expense",
                type: .incomeVsExpenseRatio,
                title: String(localized: "insights.incomeVsExpense"),
                subtitle: String(localized: "insights.ratio"),
                metric: InsightMetric(
                    value: ratio,
                    formattedValue: String(format: "%.1fx", ratio),
                    currency: nil,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: ratio >= 1.0 ? .up : .down,
                    changePercent: nil,
                    changeAbsolute: periodSummary.netFlow,
                    comparisonPeriod: Formatting.formatCurrencySmart(periodSummary.netFlow, currency: baseCurrency)
                ),
                severity: severity,
                category: .income,
                detailData: nil
            ))
        }

        let incomeInsightCount = insights.count
        let thisIncome = insights.first(where: { $0.type == .incomeGrowth })?.metric.value ?? 0
        let prevIncome = thisIncome - (insights.first(where: { $0.type == .incomeGrowth })?.trend?.changeAbsolute ?? 0)
        PerformanceLogger.InsightsMetrics.logIncomeEnd(insightCount: incomeInsightCount, thisMonth: thisIncome, prevMonth: prevIncome)
        Self.logger.debug("💵 [Insights] Income END — \(incomeInsightCount) insights")
        return insights
    }

    // MARK: - Budget Insights

    private func generateBudgetInsights(
        transactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String
    ) -> [Insight] {
        var insights: [Insight] = []
        let categoriesWithBudget = transactionStore.categories.filter { $0.budgetAmount != nil && $0.type == .expense }
        guard !categoriesWithBudget.isEmpty else {
            Self.logger.debug("💼 [Insights] Budget — SKIPPED (no budget categories)")
            return insights
        }

        PerformanceLogger.InsightsMetrics.logBudgetStart(categoriesWithBudget: categoriesWithBudget.count)
        Self.logger.debug("💼 [Insights] Budget START — \(categoriesWithBudget.count) categories with budget")

        let calendar = Calendar.current
        let now = Date()
        var budgetItems: [BudgetInsightItem] = []
        var overBudgetCount = 0

        for category in categoriesWithBudget {
            guard let progress = budgetService.budgetProgress(for: category, transactions: transactions) else {
                Self.logger.debug("   💼 \(category.name, privacy: .public): budgetProgress returned nil — SKIPPED")
                continue
            }

            let periodStart = budgetService.budgetPeriodStart(for: category)
            let daysElapsed = max(1, calendar.dateComponents([.day], from: periodStart, to: now).day ?? 1)

            let totalDays: Int
            switch category.budgetPeriod {
            case .weekly:  totalDays = 7
            case .monthly: totalDays = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            case .yearly:  totalDays = calendar.range(of: .day, in: .year,  for: now)?.count ?? 365
            }

            let daysRemaining = max(0, totalDays - daysElapsed)
            let projectedSpend = totalDays > 0
                ? (progress.spent / Double(daysElapsed)) * Double(totalDays)
                : progress.spent
            let color = Color(hex: category.colorHex)

            if progress.isOverBudget { overBudgetCount += 1 }

            Self.logger.debug("   💼 \(category.name, privacy: .public): budget=\(String(format: "%.0f", progress.budgetAmount), privacy: .public), spent=\(String(format: "%.0f", progress.spent), privacy: .public), pct=\(String(format: "%.1f%%", progress.percentage), privacy: .public), over=\(progress.isOverBudget), daysLeft=\(daysRemaining), projected=\(String(format: "%.0f", projectedSpend), privacy: .public)")

            budgetItems.append(BudgetInsightItem(
                id: category.id,
                categoryName: category.name,
                budgetAmount: progress.budgetAmount,
                spent: progress.spent,
                percentage: progress.percentage,
                isOverBudget: progress.isOverBudget,
                color: color,
                daysRemaining: daysRemaining,
                projectedSpend: projectedSpend,
                iconSource: category.iconSource
            ))
        }

        let overBudgetItems = budgetItems.filter { $0.isOverBudget }
        if !overBudgetItems.isEmpty {
            insights.append(Insight(
                id: "budget_over",
                type: .budgetOverspend,
                title: String(localized: "insights.budgetOver"),
                subtitle: String(format: String(localized: "insights.categoriesOverBudget"), overBudgetCount),
                metric: InsightMetric(
                    value: Double(overBudgetCount),
                    formattedValue: "\(overBudgetCount)",
                    currency: nil,
                    unit: String(localized: "insights.categoriesUnit")
                ),
                trend: nil,
                severity: .critical,
                category: .budget,
                detailData: .budgetProgressList(budgetItems.sorted { $0.percentage > $1.percentage })
            ))
        }

        let projectedOverspendItems = budgetItems.filter { !$0.isOverBudget && $0.projectedSpend > $0.budgetAmount }
        if !projectedOverspendItems.isEmpty {
            insights.append(Insight(
                id: "budget_projected_over",
                type: .projectedOverspend,
                title: String(localized: "insights.projectedOverspend"),
                subtitle: String(format: String(localized: "insights.categoriesAtRisk"), projectedOverspendItems.count),
                metric: InsightMetric(
                    value: Double(projectedOverspendItems.count),
                    formattedValue: "\(projectedOverspendItems.count)",
                    currency: nil,
                    unit: String(localized: "insights.categoriesUnit")
                ),
                trend: nil,
                severity: .warning,
                category: .budget,
                detailData: .budgetProgressList(projectedOverspendItems.sorted { $0.projectedSpend / $0.budgetAmount > $1.projectedSpend / $1.budgetAmount })
            ))
        }

        let underBudgetItems = budgetItems.filter { !$0.isOverBudget && $0.percentage < 80 && $0.percentage > 0 }
        if !underBudgetItems.isEmpty {
            insights.append(Insight(
                id: "budget_under",
                type: .budgetUnderutilized,
                title: String(localized: "insights.budgetUnder"),
                subtitle: String(format: String(localized: "insights.categoriesUnderBudget"), underBudgetItems.count),
                metric: InsightMetric(
                    value: Double(underBudgetItems.count),
                    formattedValue: "\(underBudgetItems.count)",
                    currency: nil,
                    unit: String(localized: "insights.categoriesUnit")
                ),
                trend: nil,
                severity: .positive,
                category: .budget,
                detailData: .budgetProgressList(underBudgetItems.sorted { $0.percentage < $1.percentage })
            ))
        }

        let projectedCount = budgetItems.filter { !$0.isOverBudget && $0.projectedSpend > $0.budgetAmount }.count
        let underCount = budgetItems.filter { !$0.isOverBudget && $0.percentage < 80 && $0.percentage > 0 }.count
        PerformanceLogger.InsightsMetrics.logBudgetEnd(insightCount: insights.count, overBudget: overBudgetCount, atRisk: projectedCount, underBudget: underCount)
        Self.logger.debug("💼 [Insights] Budget END — \(insights.count) insights, over=\(overBudgetCount), atRisk=\(projectedCount), under=\(underCount)")
        return insights
    }

    // MARK: - Recurring Insights

    private func generateRecurringInsights(baseCurrency: String) -> [Insight] {
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        guard !activeSeries.isEmpty else {
            Self.logger.debug("🔁 [Insights] Recurring — SKIPPED (no active series)")
            return []
        }

        PerformanceLogger.InsightsMetrics.logRecurringStart(activeSeries: activeSeries.count)
        Self.logger.debug("🔁 [Insights] Recurring START — \(activeSeries.count) active series")

        let recurringItems: [RecurringInsightItem] = activeSeries.map { series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let rawMonthlyEquivalent: Double
            switch series.frequency {
            case .daily:   rawMonthlyEquivalent = amount * 30
            case .weekly:  rawMonthlyEquivalent = amount * 4.33
            case .monthly: rawMonthlyEquivalent = amount
            case .yearly:  rawMonthlyEquivalent = amount / 12
            }

            // Bug 3 fix: convert each item's monthly equivalent to baseCurrency
            // before storing. Previously all amounts were summed in their native
            // currency (e.g. 100 USD treated as 100 KZT), causing wildly wrong totals.
            // CurrencyConverter.convertSync uses the same cached exchange rates as
            // the rest of the app (loaded from the national bank, 24h TTL).
            let monthlyEquivalent: Double
            if series.currency != baseCurrency,
               let converted = CurrencyConverter.convertSync(
                   amount: rawMonthlyEquivalent,
                   from: series.currency,
                   to: baseCurrency
               ) {
                monthlyEquivalent = converted
                Self.logger.debug("   🔁 converted \(String(format: "%.0f", rawMonthlyEquivalent), privacy: .public) \(series.currency, privacy: .public) → \(String(format: "%.0f", monthlyEquivalent), privacy: .public) \(baseCurrency, privacy: .public)")
            } else {
                monthlyEquivalent = rawMonthlyEquivalent
                if series.currency != baseCurrency {
                    Self.logger.warning("   🔁 ⚠️ No exchange rate for \(series.currency, privacy: .public) → \(baseCurrency, privacy: .public), using raw amount")
                }
            }

            let name = series.description.isEmpty ? series.category : series.description
            Self.logger.debug("   🔁 '\(name, privacy: .public)' \(String(describing: series.frequency), privacy: .public) \(String(format: "%.0f", amount), privacy: .public) \(series.currency, privacy: .public) → monthly=\(String(format: "%.0f", monthlyEquivalent), privacy: .public) \(baseCurrency, privacy: .public)")
            return RecurringInsightItem(
                id: series.id,
                name: name,
                amount: series.amount,
                currency: series.currency,
                frequency: series.frequency,
                kind: series.kind,
                status: series.status,
                iconSource: series.iconSource,
                monthlyEquivalent: monthlyEquivalent
            )
        }

        let totalMonthly = recurringItems.reduce(0.0) { $0 + $1.monthlyEquivalent }

        PerformanceLogger.InsightsMetrics.logRecurringEnd(totalMonthly: totalMonthly, currency: baseCurrency)
        Self.logger.debug("🔁 [Insights] Recurring END — totalMonthly=\(String(format: "%.0f", totalMonthly), privacy: .public) \(baseCurrency, privacy: .public)")

        return [Insight(
            id: "total_recurring",
            type: .totalRecurringCost,
            title: String(localized: "insights.totalRecurring"),
            subtitle: String(format: String(localized: "insights.activeRecurring"), activeSeries.count),
            metric: InsightMetric(
                value: totalMonthly,
                formattedValue: Formatting.formatCurrencySmart(totalMonthly, currency: baseCurrency),
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: nil,
            severity: totalMonthly > 0 ? .neutral : .positive,
            category: .recurring,
            detailData: .recurringList(recurringItems.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent })
        )]
    }

    // MARK: - Cash Flow Insights

    private func generateCashFlowInsights(
        allTransactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        // Choose number of months based on the selected filter preset:
        // "Last Year" / "All Time" → 12 months; anything shorter → 6 months.
        let trendMonths: Int
        switch timeFilter.preset {
        case .lastYear, .allTime:
            trendMonths = 12
        default:
            trendMonths = 6
        }

        PerformanceLogger.InsightsMetrics.logCashFlowStart(months: trendMonths)
        Self.logger.debug("💸 [Insights] CashFlow START — computing \(trendMonths)-month trend")

        // Bug 1 fix: use the filter's INCLUSIVE end as anchor so historical filters
        // (Last Year, Last 3 Months) produce month points within their period.
        // timeFilter.dateRange().end is EXCLUSIVE (e.g. "Last Month" Jan → Feb 1).
        // Using Feb 1 as anchor causes startOfMonth(Feb 1) = Feb 2026 as the last slot,
        // which has 0 transactions and makes the chart, SummaryHeader, and MoM all show 0.
        // FIX: subtract 1 second to get the inclusive last instant of the filter period
        // (Feb 1 00:00:00 → Jan 31 23:59:59), so startOfMonth gives Jan → last slot = Jan ✓.
        let filterEndExclusive = timeFilter.dateRange().end
        let calendar = Calendar.current
        // For current/future-ending filters keep filterEnd as-is (they end today or later).
        let anchorDate: Date
        if Calendar.current.isDateInToday(filterEndExclusive) || filterEndExclusive > Date() {
            anchorDate = Date()
        } else {
            anchorDate = calendar.date(byAdding: .second, value: -1, to: filterEndExclusive) ?? filterEndExclusive
        }
        guard let windowStart = calendar.date(byAdding: .month, value: -trendMonths, to: startOfMonth(calendar, for: anchorDate)) else {
            Self.logger.debug("💸 [Insights] CashFlow — SKIPPED (could not compute \(trendMonths)-month window)")
            return []
        }
        let windowTransactions = filterService.filterByTimeRange(allTransactions, start: windowStart, end: filterEndExclusive)
        Self.logger.debug("💸 [Insights] CashFlow — \(trendMonths)-month window \(Self.monthYearFormatter.string(from: windowStart), privacy: .public) → \(Self.monthYearFormatter.string(from: anchorDate), privacy: .public) (anchor), transactions=\(windowTransactions.count) (was \(allTransactions.count))")

        let monthlyData = computeMonthlyDataPoints(
            transactions: windowTransactions,
            months: trendMonths,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            anchorDate: anchorDate
        )
        guard monthlyData.count >= 2 else {
            Self.logger.debug("💸 [Insights] CashFlow — SKIPPED (only \(monthlyData.count) month(s) of data, need ≥2)")
            return []
        }

        var insights: [Insight] = []

        // 1. Net cash flow trend
        if let latest = monthlyData.last {
            let avgNetFlow = monthlyData.reduce(0.0) { $0 + $1.netFlow } / Double(monthlyData.count)
            let severity: InsightSeverity = latest.netFlow > 0 ? .positive : (latest.netFlow < 0 ? .critical : .neutral)
            Self.logger.debug("💸 [Insights] Net cash flow — latest=\(String(format: "%.0f", latest.netFlow), privacy: .public), avg=\(String(format: "%.0f", avgNetFlow), privacy: .public), severity=\(String(describing: severity), privacy: .public)")

            insights.append(Insight(
                id: "net_cashflow",
                type: .netCashFlow,
                title: String(localized: "insights.netCashFlow"),
                subtitle: latest.label,
                metric: InsightMetric(
                    value: latest.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(latest.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: latest.netFlow > avgNetFlow ? .up : (latest.netFlow < avgNetFlow ? .down : .flat),
                    changePercent: nil,
                    changeAbsolute: latest.netFlow - avgNetFlow,
                    comparisonPeriod: String(localized: "insights.vsAverage")
                ),
                severity: severity,
                category: .cashFlow,
                detailData: .monthlyTrend(monthlyData)
            ))
        }

        // 2. Best month
        if let best = monthlyData.max(by: { $0.netFlow < $1.netFlow }) {
            insights.append(Insight(
                id: "best_month",
                type: .bestMonth,
                title: String(localized: "insights.bestMonth"),
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .positive,
                category: .cashFlow,
                detailData: .monthlyTrend(monthlyData)
            ))
        }

        // 3. Projected balance (30 days ahead)
        // Use real account balances from BalanceCoordinator (via callback), not initialBalance
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }

        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        let monthlyRecurringNet = activeSeries.reduce(0.0) { total, series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let monthly: Double
            switch series.frequency {
            case .daily:   monthly = amount * 30
            case .weekly:  monthly = amount * 4.33
            case .monthly: monthly = amount
            case .yearly:  monthly = amount / 12
            }
            let isIncome = transactionStore.categories.first { $0.name == series.category }?.type == .income
            return total + (isIncome ? monthly : -monthly)
        }

        let projectedBalance = currentBalance + monthlyRecurringNet

        let accountCount = transactionStore.accounts.count
        Self.logger.debug("💸 [Insights] Projected balance — accounts=\(accountCount), currentBalance=\(String(format: "%.0f", currentBalance), privacy: .public), recurringNet=\(String(format: "%+.0f", monthlyRecurringNet), privacy: .public), projected=\(String(format: "%.0f", projectedBalance), privacy: .public) \(baseCurrency, privacy: .public)")

        // Show the recurring IMPACT (delta) as the primary metric rather than the total projected
        // balance. Previously the card showed "46,671,832 KZT" which was confusing — it's a huge
        // number with no context. Showing the monthly recurring delta (-14,974 KZT) is more useful:
        // the user can immediately see how their subscriptions affect their balance each month.
        // The projected total balance is shown in the comparison line as context.
        let projectedMetricValue = monthlyRecurringNet
        let projectedMetricFormatted: String
        if monthlyRecurringNet >= 0 {
            projectedMetricFormatted = "+" + Formatting.formatCurrencySmart(monthlyRecurringNet, currency: baseCurrency)
        } else {
            projectedMetricFormatted = Formatting.formatCurrencySmart(monthlyRecurringNet, currency: baseCurrency)
        }

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: String(localized: "insights.in30Days"),
            metric: InsightMetric(
                value: projectedMetricValue,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: InsightTrend(
                direction: monthlyRecurringNet >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (monthlyRecurringNet / currentBalance) * 100 : nil,
                changeAbsolute: monthlyRecurringNet,
                comparisonPeriod: String(localized: "insights.currentBalance") + ": "
                    + Formatting.formatCurrencySmart(currentBalance, currency: baseCurrency)
            ),
            severity: projectedBalance >= 0 ? .positive : .critical,
            category: .cashFlow,
            detailData: nil
        ))

        PerformanceLogger.InsightsMetrics.logCashFlowEnd(
            insightCount: insights.count,
            latestNetFlow: monthlyData.last?.netFlow ?? 0,
            projectedBalance: projectedBalance
        )
        Self.logger.debug("💸 [Insights] CashFlow END — \(insights.count) insights generated")
        return insights
    }

    // MARK: - Category Deep Dive

    func generateCategoryDeepDive(
        categoryName: String,
        allTransactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> (subcategories: [SubcategoryBreakdownItem], monthlyTrend: [MonthlyDataPoint]) {
        // All category transactions ever (used for the 6-month rolling trend chart)
        let allCategoryTransactions = allTransactions.filter { $0.category == categoryName && $0.type == .expense }

        // Period-scoped transactions for the subcategory breakdown (respects the selected filter)
        let range = timeFilter.dateRange()
        let periodCategoryTransactions = filterService.filterByTimeRange(allCategoryTransactions, start: range.start, end: range.end)

        let totalAmount = periodCategoryTransactions.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }

        // Subcategory breakdown — scoped to the selected time period
        let subcategories = Dictionary(grouping: periodCategoryTransactions, by: { $0.subcategory ?? String(localized: "insights.noSubcategory") })
            .map { key, txns -> SubcategoryBreakdownItem in
                let amount = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                return SubcategoryBreakdownItem(
                    id: key,
                    name: key,
                    amount: amount,
                    percentage: totalAmount > 0 ? (amount / totalAmount) * 100 : 0
                )
            }
            .sorted { $0.amount > $1.amount }

        // Monthly trend always uses the last 6 months anchored to the filter end
        // (same logic as generateCashFlowInsights — use inclusive anchor)
        let calendar = Calendar.current
        let filterEndExclusive = timeFilter.dateRange().end
        let anchor: Date
        if Calendar.current.isDateInToday(filterEndExclusive) || filterEndExclusive > Date() {
            anchor = Date()
        } else {
            anchor = calendar.date(byAdding: .second, value: -1, to: filterEndExclusive) ?? filterEndExclusive
        }
        var monthlyTrend: [MonthlyDataPoint] = []
        monthlyTrend.reserveCapacity(6)

        for i in (0..<6).reversed() {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -i, to: startOfMonth(calendar, for: anchor)),
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            let monthTotal = filterService
                .filterByTimeRange(allCategoryTransactions, start: monthStart, end: monthEnd)
                .reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }

            monthlyTrend.append(MonthlyDataPoint(
                id: Self.yearMonthFormatter.string(from: monthStart),
                month: monthStart,
                income: 0,
                expenses: monthTotal,
                netFlow: -monthTotal,
                label: Self.monthAbbrevFormatter.string(from: monthStart)
            ))
        }

        return (subcategories, monthlyTrend)
    }

    // MARK: - Granularity-based API (Phase 18)

    /// Generates all insights for a given granularity. Data is ALWAYS all-time; granularity
    /// controls how charts group and compare periods.
    func generateAllInsights(
        granularity: InsightGranularity,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        let allTransactions = Array(transactionStore.transactions)

        // For period summary: compute all-time income/expense totals
        let (allIncome, allExpenses) = calculateMonthlySummary(
            transactions: allTransactions,
            baseCurrency: baseCurrency,
            currencyService: currencyService
        )
        let periodSummary = PeriodSummary(
            totalIncome: allIncome,
            totalExpenses: allExpenses,
            netFlow: allIncome - allExpenses
        )

        // Build a TimeFilter that covers all-time for budget/spending/income helpers
        let firstDate = allTransactions
            .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
            .min()
        let allTimeFilter = TimeFilter(preset: .allTime)
        _ = firstDate // used below for computePeriodDataPoints

        var insights: [Insight] = []

        insights.append(contentsOf: generateSpendingInsights(
            filtered: allTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: allTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateIncomeInsights(
            filtered: allTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: allTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: allTransactions,
            timeFilter: allTimeFilter,
            baseCurrency: baseCurrency
        ))

        insights.append(contentsOf: generateRecurringInsights(baseCurrency: baseCurrency))

        // Cash flow section — use period data points for the selected granularity
        let periodPoints = computePeriodDataPoints(
            transactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            firstTransactionDate: firstDate
        )
        insights.append(contentsOf: generateCashFlowInsightsFromPeriodPoints(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor
        ))

        // Wealth card
        insights.append(contentsOf: generateWealthInsights(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            balanceFor: balanceFor
        ))

        return insights
    }

    // MARK: - Period Data Points (Phase 18)

    /// Groups all transactions into PeriodDataPoint buckets according to granularity.
    func computePeriodDataPoints(
        transactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        firstTransactionDate: Date? = nil
    ) -> [PeriodDataPoint] {
        guard !transactions.isEmpty else { return [] }

        let dateFormatter = DateFormatters.dateFormatter
        let calendar = Calendar.current

        // Determine data window
        let firstDate = firstTransactionDate
            ?? transactions.compactMap { dateFormatter.date(from: $0.date) }.min()
            ?? Date()
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Build ordered list of all keys in this window
        var orderedKeys: [String] = []
        var keySet = Set<String>()
        var cursor = windowStart
        while cursor < windowEnd {
            let key = granularity.groupingKey(for: cursor)
            if !keySet.contains(key) {
                orderedKeys.append(key)
                keySet.insert(key)
            }
            // Advance cursor by one unit
            switch granularity {
            case .week:    cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? windowEnd
            case .month:   cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? windowEnd
            case .quarter: cursor = calendar.date(byAdding: .month, value: 3, to: cursor) ?? windowEnd
            case .year:    cursor = calendar.date(byAdding: .year, value: 1, to: cursor) ?? windowEnd
            case .allTime: cursor = windowEnd
            }
        }

        // Aggregate transactions into buckets
        var incomeByKey = [String: Double]()
        var expensesByKey = [String: Double]()

        for tx in transactions {
            guard let txDate = dateFormatter.date(from: tx.date),
                  txDate >= windowStart, txDate < windowEnd else { continue }
            let key = granularity.groupingKey(for: txDate)
            let amount = currencyService.getConvertedAmountOrCompute(transaction: tx, to: baseCurrency)
            switch tx.type {
            case .income:  incomeByKey[key, default: 0] += amount
            case .expense: expensesByKey[key, default: 0] += amount
            default: break
            }
        }

        // Build result array in chronological order
        return orderedKeys.map { key in
            let periodStart = granularity.periodStart(for: key)
            let periodEnd: Date
            switch granularity {
            case .week:    periodEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: periodStart) ?? periodStart
            case .month:   periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart
            case .quarter: periodEnd = calendar.date(byAdding: .month, value: 3, to: periodStart) ?? periodStart
            case .year:    periodEnd = calendar.date(byAdding: .year, value: 1, to: periodStart) ?? periodStart
            case .allTime: periodEnd = windowEnd
            }
            return PeriodDataPoint(
                id: key,
                granularity: granularity,
                key: key,
                periodStart: periodStart,
                periodEnd: periodEnd,
                label: granularity.periodLabel(for: key),
                income: incomeByKey[key] ?? 0,
                expenses: expensesByKey[key] ?? 0,
                cumulativeBalance: nil
            )
        }
    }

    // MARK: - Cash Flow from Period Points (Phase 18)

    private func generateCashFlowInsightsFromPeriodPoints(
        periodPoints: [PeriodDataPoint],
        allTransactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        guard periodPoints.count >= 2 else { return [] }

        var insights: [Insight] = []
        let currentKey = granularity.currentPeriodKey
        let latest = periodPoints.last(where: { $0.key == currentKey }) ?? periodPoints.last!
        let avgNetFlow = periodPoints.reduce(0.0) { $0 + $1.netFlow } / Double(periodPoints.count)

        // 1. Net cash flow trend
        let severity: InsightSeverity = latest.netFlow > 0 ? .positive : (latest.netFlow < 0 ? .critical : .neutral)
        insights.append(Insight(
            id: "net_cashflow",
            type: .netCashFlow,
            title: String(localized: "insights.netCashFlow"),
            subtitle: latest.label,
            metric: InsightMetric(
                value: latest.netFlow,
                formattedValue: Formatting.formatCurrencySmart(latest.netFlow, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: latest.netFlow > avgNetFlow ? .up : (latest.netFlow < avgNetFlow ? .down : .flat),
                changePercent: nil,
                changeAbsolute: latest.netFlow - avgNetFlow,
                comparisonPeriod: String(localized: "insights.vsAverage")
            ),
            severity: severity,
            category: .cashFlow,
            detailData: .periodTrend(periodPoints)
        ))

        // 2. Best period
        if let best = periodPoints.max(by: { $0.netFlow < $1.netFlow }) {
            insights.append(Insight(
                id: "best_month",
                type: .bestMonth,
                title: String(localized: "insights.bestMonth"),
                subtitle: best.label,
                metric: InsightMetric(
                    value: best.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(best.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .positive,
                category: .cashFlow,
                detailData: .periodTrend(periodPoints)
            ))
        }

        // 3. Projected balance (recurring delta)
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        let monthlyRecurringNet = activeSeries.reduce(0.0) { total, series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let monthly: Double
            switch series.frequency {
            case .daily:   monthly = amount * 30
            case .weekly:  monthly = amount * 4.33
            case .monthly: monthly = amount
            case .yearly:  monthly = amount / 12
            }
            let isIncome = transactionStore.categories.first { $0.name == series.category }?.type == .income
            return total + (isIncome ? monthly : -monthly)
        }

        let projectedBalance = currentBalance + monthlyRecurringNet
        let projectedMetricFormatted = monthlyRecurringNet >= 0
            ? "+" + Formatting.formatCurrencySmart(monthlyRecurringNet, currency: baseCurrency)
            : Formatting.formatCurrencySmart(monthlyRecurringNet, currency: baseCurrency)

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: String(localized: "insights.in30Days"),
            metric: InsightMetric(
                value: monthlyRecurringNet,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: InsightTrend(
                direction: monthlyRecurringNet >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (monthlyRecurringNet / currentBalance) * 100 : nil,
                changeAbsolute: monthlyRecurringNet,
                comparisonPeriod: String(localized: "insights.currentBalance") + ": "
                    + Formatting.formatCurrencySmart(currentBalance, currency: baseCurrency)
            ),
            severity: projectedBalance >= 0 ? .positive : .critical,
            category: .cashFlow,
            detailData: nil
        ))

        return insights
    }

    // MARK: - Wealth Insights (Phase 18)

    func generateWealthInsights(
        periodPoints: [PeriodDataPoint],
        allTransactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        let accounts = transactionStore.accounts
        guard !accounts.isEmpty else { return [] }

        // Total current wealth = sum of all account balances (from BalanceCoordinator)
        let totalWealth = accounts.reduce(0.0) { $0 + balanceFor($1.id) }

        // Account breakdown for detail view
        let accountItems: [AccountInsightItem] = accounts.map { account in
            AccountInsightItem(
                id: account.id,
                accountName: account.name,
                currency: account.currency,
                balance: balanceFor(account.id),
                transactionCount: allTransactions.filter { $0.accountId == account.id }.count,
                lastActivityDate: nil,
                iconSource: account.iconSource
            )
        }.sorted { $0.balance > $1.balance }

        // Build cumulative balance data points
        // Start from an approximate "initial balance" and accumulate net flows per period
        let initialBalance = totalWealth - periodPoints.reduce(0.0) { $0 + $1.netFlow }
        var running = initialBalance
        let cumulativePoints: [PeriodDataPoint] = periodPoints.map { point in
            running += point.netFlow
            return PeriodDataPoint(
                id: point.id,
                granularity: point.granularity,
                key: point.key,
                periodStart: point.periodStart,
                periodEnd: point.periodEnd,
                label: point.label,
                income: point.income,
                expenses: point.expenses,
                cumulativeBalance: running
            )
        }

        // MoP (month/period-over-period) comparison
        let currentKey = granularity.currentPeriodKey
        let prevKey = granularity.previousPeriodKey
        let currentPeriodNetFlow = periodPoints.first(where: { $0.key == currentKey })?.netFlow ?? 0
        let prevPeriodNetFlow = periodPoints.first(where: { $0.key == prevKey })?.netFlow ?? 0

        let changePercent: Double? = prevPeriodNetFlow != 0
            ? ((currentPeriodNetFlow - prevPeriodNetFlow) / abs(prevPeriodNetFlow)) * 100
            : nil
        let direction: TrendDirection = currentPeriodNetFlow > 0 ? .up : (currentPeriodNetFlow < 0 ? .down : .flat)

        return [Insight(
            id: "total_wealth",
            type: .totalWealth,
            title: String(localized: "insights.wealth.title"),
            subtitle: String(localized: "insights.wealth.subtitle"),
            metric: InsightMetric(
                value: totalWealth,
                formattedValue: Formatting.formatCurrencySmart(totalWealth, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentPeriodNetFlow,
                comparisonPeriod: granularity.comparisonPeriodName
            ),
            severity: totalWealth >= 0 ? .positive : .critical,
            category: .wealth,
            detailData: .wealthBreakdown(accountItems)
        )]
    }

    // MARK: - Helpers

    /// Lightweight summary value type used internally to avoid constructing the full `Summary` model.
    /// We cannot use `Summary` directly because it requires fields (currency, startDate, endDate,
    /// plannedAmount, totalInternalTransfers) that are irrelevant here and would force us to call
    /// `queryService.calculateSummary` — which hits the contaminating global cache.
    private struct PeriodSummary {
        let totalIncome: Double
        let totalExpenses: Double
        let netFlow: Double
    }

    /// Returns the amount in baseCurrency. Uses cached convertedAmount when available.
    private func resolveAmount(_ transaction: Transaction, baseCurrency: String) -> Double {
        guard transaction.currency != baseCurrency else { return transaction.amount }
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Inline helper to avoid Calendar extension conflicts with Date+Helpers.swift
    private func startOfMonth(_ calendar: Calendar, for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Calculates income/expenses for a specific transaction slice WITHOUT using
    /// the global TransactionCacheManager cache.
    ///
    /// ROOT CAUSE FIX for identical monthly data:
    /// `TransactionQueryService.calculateSummary` has a global summary cache in
    /// `cacheManager.cachedSummary`. The first call for month[0] populates it;
    /// every subsequent call for months[1..5] hits `!summaryCacheInvalidated` and
    /// returns the cached month[0] result — even though a different transaction
    /// slice was passed. Since each monthly slice is independent, we must bypass
    /// the cache entirely and do the arithmetic directly.
    private func calculateMonthlySummary(
        transactions: [Transaction],
        baseCurrency: String,
        currencyService: TransactionCurrencyService
    ) -> (income: Double, expenses: Double) {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatters.dateFormatter
        var income: Double = 0
        var expenses: Double = 0

        for tx in transactions {
            guard let txDate = dateFormatter.date(from: tx.date), txDate <= today else { continue }
            let amount = currencyService.getConvertedAmountOrCompute(transaction: tx, to: baseCurrency)
            switch tx.type {
            case .income:  income += amount
            case .expense: expenses += amount
            default: break
            }
        }
        return (income, expenses)
    }
}
