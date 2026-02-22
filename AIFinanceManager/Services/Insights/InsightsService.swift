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

    // MARK: - Monthly Data Points (Phase 22: reads from MonthlyAggregateService)

    /// Compute monthly data points for chart display.
    ///
    /// Phase 22 optimization: reads pre-computed MonthlyAggregateEntity records from CoreData
    /// instead of scanning all transactions (O(M) lookups vs the previous O(N×M) passes).
    /// Falls back to the original transaction-scan path if aggregates are unavailable
    /// (e.g. on first launch before a full rebuild).
    func computeMonthlyDataPoints(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,  // kept for API compatibility; not used inside
        currencyService: TransactionCurrencyService,
        anchorDate: Date? = nil
    ) -> [MonthlyDataPoint] {
        PerformanceLogger.InsightsMetrics.logMonthlyPointStart(months: months, transactionCount: transactions.count)

        let anchor = anchorDate ?? Date()

        // Phase 22: Try fast path — read from persistent MonthlyAggregateEntity
        let aggregates = transactionStore.monthlyAggregateService.fetchLast(
            months,
            anchor: anchor,
            currency: baseCurrency
        )

        // If we got a full set of aggregate records, use them directly (O(M) fetch)
        if aggregates.count == months {
            Self.logger.debug("⚡️ [Insights] Monthly points FAST PATH — \(months) months from CoreData aggregates")
            let dataPoints: [MonthlyDataPoint] = aggregates.map { agg in
                let monthDate = Calendar.current.date(
                    from: DateComponents(year: agg.year, month: agg.month, day: 1)
                ) ?? Date()
                return MonthlyDataPoint(
                    id: Self.yearMonthFormatter.string(from: monthDate),
                    month: monthDate,
                    income: agg.totalIncome,
                    expenses: agg.totalExpenses,
                    netFlow: agg.netFlow,
                    label: Self.monthYearFormatter.string(from: monthDate)
                )
            }
            PerformanceLogger.InsightsMetrics.logMonthlyPointEnd(pointCount: dataPoints.count)
            Self.logger.debug("📅 [Insights] Monthly points END (fast) — \(dataPoints.count) points")
            return dataPoints
        }

        // Phase 22 fallback: aggregates not ready yet (first launch) — use transaction scan
        Self.logger.debug("📅 [Insights] Monthly points SLOW PATH — aggregates count=\(aggregates.count) (expected \(months)), scanning transactions")
        return computeMonthlyDataPointsSlow(
            transactions: transactions,
            months: months,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            anchor: anchor
        )
    }

    /// Original O(N×M) implementation used as fallback before aggregates are built.
    private func computeMonthlyDataPointsSlow(
        transactions: [Transaction],
        months: Int,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        anchor: Date
    ) -> [MonthlyDataPoint] {
        let calendar = Calendar.current
        var dataPoints: [MonthlyDataPoint] = []
        dataPoints.reserveCapacity(months)

        for i in (0..<months).reversed() {
            guard
                let monthStart = calendar.date(byAdding: .month, value: -i, to: startOfMonth(calendar, for: anchor)),
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { continue }

            let monthTransactions = filterService.filterByTimeRange(transactions, start: monthStart, end: monthEnd)
            let (monthIncome, monthExpenses) = calculateMonthlySummary(
                transactions: monthTransactions,
                baseCurrency: baseCurrency,
                currencyService: currencyService
            )
            let monthNetFlow = monthIncome - monthExpenses
            let label = Self.monthYearFormatter.string(from: monthStart)

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
        currencyService: TransactionCurrencyService,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = []
    ) -> [Insight] {
        var insights: [Insight] = []
        let expenses = filterService.filterByType(filtered, type: .expense)
        guard !expenses.isEmpty else {
            Self.logger.debug("🛒 [Insights] Spending — SKIPPED (no expenses in period)")
            return insights
        }

        // 1. Top spending category
        // Phase 31: Narrow to the current granularity bucket when available so the breakdown
        // reflects only the current week / month / quarter / year — not the full window.
        let currentBucketPoint = granularity.flatMap { gran in
            periodPoints.first(where: { $0.key == gran.currentPeriodKey })
        }

        // Date range and expenses scoped to the current bucket (or full window as fallback)
        let topRange: (start: Date, end: Date)
        let topExpenses: [Transaction]
        let topTotalExpenses: Double

        if let cp = currentBucketPoint {
            topRange = (cp.periodStart, cp.periodEnd)
            topExpenses = filterService.filterByTimeRange(expenses, start: cp.periodStart, end: cp.periodEnd)
            topTotalExpenses = cp.expenses
        } else {
            topRange = timeFilter.dateRange()
            topExpenses = expenses
            topTotalExpenses = periodSummary.totalExpenses
        }

        // Phase 22: Try fast path — read category totals from CategoryAggregateService (O(M) fetch)
        let aggCategories = transactionStore.categoryAggregateService.fetchRange(
            from: topRange.start, to: topRange.end, currency: baseCurrency
        )

        // Build sortedCategories from aggregates when available; fall back to transaction scan
        let sortedCategories: [(key: String, total: Double)]
        if !aggCategories.isEmpty {
            Self.logger.debug("⚡️ [Insights] Category spending FAST PATH — \(aggCategories.count) categories from CoreData")
            sortedCategories = aggCategories.map { (key: $0.categoryName, total: $0.totalExpenses) }
        } else {
            // Slow path: group current-bucket expenses by category and sum (O(N))
            let bucketGroups = Dictionary(grouping: topExpenses, by: { $0.category })
            sortedCategories = bucketGroups
                .map { key, txns in
                    let total = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                    return (key: key, total: total)
                }
                .sorted { $0.total > $1.total }
        }

        // For subcategory breakdown, build a lookup from current-bucket expenses
        let categoryGroups = Dictionary(grouping: topExpenses, by: { $0.category })

        let topCategoryName = sortedCategories.first?.key ?? "—"
        let topCategoryAmount = sortedCategories.first?.total ?? 0
        PerformanceLogger.InsightsMetrics.logSpendingStart(expenseCount: topExpenses.count, categoryCount: sortedCategories.count)
        Self.logger.debug("🛒 [Insights] Spending — bucket_expenses=\(topExpenses.count), categories=\(sortedCategories.count), top='\(topCategoryName, privacy: .public)' (\(String(format: "%.0f", topCategoryAmount), privacy: .public) \(baseCurrency, privacy: .public))")
        for cat in sortedCategories.prefix(5) {
            let pct = topTotalExpenses > 0 ? (cat.total / topTotalExpenses) * 100 : 0
            Self.logger.debug("   🛒 \(cat.key, privacy: .public): \(String(format: "%.0f", cat.total), privacy: .public) (\(String(format: "%.1f%%", pct), privacy: .public))")
        }

        if let top = sortedCategories.first {
            let percentage = topTotalExpenses > 0
                ? (top.total / topTotalExpenses) * 100
                : 0

            // Phase 30: show ALL categories (computation is in background Task.detached, no UI lag).
            let breakdownItems: [CategoryBreakdownItem] = sortedCategories.map { item in
                let pct = topTotalExpenses > 0 ? (item.total / topTotalExpenses) * 100 : 0
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

        // 2. Period-over-period spending change.
        // Phase 30: use granularity bucket lookup (currentPeriodKey / previousPeriodKey) when
        // periodPoints are available; fall back to legacy calendar-month O(N) scan otherwise.
        // Skip for .allTime — there is no meaningful "previous all-time period" to compare against,
        // and previousPeriodKey == currentPeriodKey for allTime which would produce a two-point
        // chart with duplicate labels (→ fatal crash in axisLabelMap).
        if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let thisTotal    = currentPoint?.expenses ?? 0
            let prevTotal    = prevPoint?.expenses ?? 0

            Self.logger.debug("🔄 [Insights] MoP spending (granularity) — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if let prevPoint, prevTotal > 0 {
                let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 20 ? .warning : (changePercent < -10 ? .positive : .neutral)

                insights.append(Insight(
                    id: "mom_spending",
                    type: .monthOverMonthChange,
                    title: gran.monthOverMonthTitle,
                    subtitle: gran.comparisonPeriodName,
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
                        comparisonPeriod: gran.comparisonPeriodName
                    ),
                    severity: severity,
                    category: .spending,
                    detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
                ))
            }
        } else {
            // Legacy path: calendar-month O(N) scan (used when called from old timeFilter API).
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let thisMonthStart = startOfMonth(calendar, for: refDate)
            let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
            let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
            let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

            if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
               let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {
                var thisMonthTotal: Double = 0
                var prevMonthTotal: Double = 0
                let dateFormatter = DateFormatters.dateFormatter
                for tx in allTransactions where tx.type == .expense {
                    guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                    let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                    if txDate >= thisMonthStart && txDate < thisMonthEnd { thisMonthTotal += amount }
                    else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevMonthTotal += amount }
                }
                if prevMonthTotal > 0 {
                    let changePercent = ((thisMonthTotal - prevMonthTotal) / prevMonthTotal) * 100
                    let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                    let severity: InsightSeverity = changePercent > 20 ? .warning : (changePercent < -10 ? .positive : .neutral)
                    insights.append(Insight(
                        id: "mom_spending",
                        type: .monthOverMonthChange,
                        title: String(localized: "insights.monthOverMonth"),
                        subtitle: String(localized: "insights.vsPreviousPeriod"),
                        metric: InsightMetric(
                            value: thisMonthTotal,
                            formattedValue: Formatting.formatCurrencySmart(thisMonthTotal, currency: baseCurrency),
                            currency: baseCurrency, unit: nil
                        ),
                        trend: InsightTrend(
                            direction: direction, changePercent: changePercent,
                            changeAbsolute: thisMonthTotal - prevMonthTotal,
                            comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
                        ),
                        severity: severity, category: .spending, detailData: nil
                    ))
                }
            }
        }

        // 3. Average daily spending.
        // Phase 30: compute from current/previous granularity bucket when available;
        // fall back to period-range day-count otherwise.
        if let gran = granularity, !periodPoints.isEmpty {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let cal = Calendar.current
            let currentDays = currentPoint.map { max(1, cal.dateComponents([.day], from: $0.periodStart, to: $0.periodEnd).day ?? 1) } ?? 1
            let prevDays    = prevPoint.map    { max(1, cal.dateComponents([.day], from: $0.periodStart, to: $0.periodEnd).day ?? 1) } ?? 1
            let currentAvgDaily = (currentPoint?.expenses ?? 0) / Double(currentDays)
            let prevAvgDaily    = (prevPoint?.expenses ?? 0)    / Double(prevDays)
            let changePercent   = prevAvgDaily > 0 ? ((currentAvgDaily - prevAvgDaily) / prevAvgDaily) * 100 : 0.0
            let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)

            Self.logger.debug("📆 [Insights] Avg daily (granularity) — current=\(String(format: "%.0f", currentAvgDaily), privacy: .public), prev=\(String(format: "%.0f", prevAvgDaily), privacy: .public), change=\(String(format: "%+.1f%%", changePercent), privacy: .public)")

            insights.append(Insight(
                id: "avg_daily",
                type: .averageDailySpending,
                title: String(localized: "insights.avgDailySpending"),
                subtitle: currentPoint?.label ?? "",
                metric: InsightMetric(
                    value: currentAvgDaily,
                    formattedValue: Formatting.formatCurrencySmart(currentAvgDaily, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: prevAvgDaily > 0 ? InsightTrend(
                    direction: direction,
                    changePercent: changePercent,
                    changeAbsolute: currentAvgDaily - prevAvgDaily,
                    comparisonPeriod: gran.comparisonPeriodName
                ) : nil,
                severity: .neutral,
                category: .spending,
                detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
            ))
        } else {
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let periodRange = timeFilter.dateRange()
            let days = max(1, calendar.dateComponents([.day], from: periodRange.start, to: min(periodRange.end, refDate)).day ?? 1)
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
        }

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
        currencyService: TransactionCurrencyService,
        granularity: InsightGranularity? = nil,
        periodPoints: [PeriodDataPoint] = []
    ) -> [Insight] {
        var insights: [Insight] = []
        let incomeTransactions = filterService.filterByType(filtered, type: .income)
        guard !incomeTransactions.isEmpty else {
            Self.logger.debug("💵 [Insights] Income — SKIPPED (no income transactions in period)")
            return insights
        }

        PerformanceLogger.InsightsMetrics.logIncomeStart(incomeCount: incomeTransactions.count)
        Self.logger.debug("💵 [Insights] Income START — incomeTransactions=\(incomeTransactions.count)")

        // 1. Income growth (period-over-period).
        // Phase 30: use granularity bucket lookup when periodPoints available; fall back to legacy scan.
        // Skip .allTime — same reason as spending MoM: previousPeriodKey == currentPeriodKey → duplicate labels.
        if let gran = granularity, !periodPoints.isEmpty, gran != .allTime {
            let currentPoint = periodPoints.first(where: { $0.key == gran.currentPeriodKey })
            let prevPoint    = periodPoints.first(where: { $0.key == gran.previousPeriodKey })
            let thisTotal    = currentPoint?.income ?? 0
            let prevTotal    = prevPoint?.income ?? 0

            Self.logger.debug("💵 [Insights] Income growth (granularity) — this=\(String(format: "%.0f", thisTotal), privacy: .public), prev=\(String(format: "%.0f", prevTotal), privacy: .public)")

            if let prevPoint, prevTotal > 0 {
                let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                let severity: InsightSeverity = changePercent > 10 ? .positive : (changePercent < -10 ? .warning : .neutral)

                insights.append(Insight(
                    id: "income_growth",
                    type: .incomeGrowth,
                    title: String(localized: "insights.incomeGrowth"),
                    subtitle: gran.comparisonPeriodName,
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
                        comparisonPeriod: gran.comparisonPeriodName
                    ),
                    severity: severity,
                    category: .income,
                    detailData: .periodTrend([prevPoint, currentPoint].compactMap { $0 })
                ))
            }
        } else {
            // Legacy path: calendar-month O(N) scan.
            let calendar = Calendar.current
            let refDate = momReferenceDate(for: timeFilter)
            let thisMonthStart = startOfMonth(calendar, for: refDate)
            let fullMonthEnd = calendar.date(byAdding: .month, value: 1, to: thisMonthStart) ?? refDate
            let refDatePlusOneDay = calendar.date(byAdding: .day, value: 1, to: refDate) ?? fullMonthEnd
            let thisMonthEnd = min(fullMonthEnd, refDatePlusOneDay)

            if let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
               let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart) {
                var thisTotal: Double = 0
                var prevTotal: Double = 0
                let dateFormatter = DateFormatters.dateFormatter
                for tx in allTransactions where tx.type == .income {
                    guard let txDate = dateFormatter.date(from: tx.date) else { continue }
                    let amount = resolveAmount(tx, baseCurrency: baseCurrency)
                    if txDate >= thisMonthStart && txDate < thisMonthEnd { thisTotal += amount }
                    else if txDate >= prevMonthStart && txDate < prevMonthEnd { prevTotal += amount }
                }
                if prevTotal > 0 {
                    let changePercent = ((thisTotal - prevTotal) / prevTotal) * 100
                    let direction: TrendDirection = changePercent > 2 ? .up : (changePercent < -2 ? .down : .flat)
                    let severity: InsightSeverity = changePercent > 10 ? .positive : (changePercent < -10 ? .warning : .neutral)
                    insights.append(Insight(
                        id: "income_growth", type: .incomeGrowth,
                        title: String(localized: "insights.incomeGrowth"),
                        subtitle: String(localized: "insights.vsPreviousPeriod"),
                        metric: InsightMetric(value: thisTotal,
                            formattedValue: Formatting.formatCurrencySmart(thisTotal, currency: baseCurrency),
                            currency: baseCurrency, unit: nil),
                        trend: InsightTrend(direction: direction, changePercent: changePercent,
                            changeAbsolute: thisTotal - prevTotal,
                            comparisonPeriod: String(localized: "insights.vsPreviousPeriod")),
                        severity: severity, category: .income, detailData: nil
                    ))
                }
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
                detailData: periodPoints.isEmpty ? nil : .periodTrend(periodPoints)
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

        // Phase 23-C P15: single pass to partition budget items (was 5 separate filter calls)
        var overBudgetItems: [BudgetInsightItem] = []
        var projectedOverspendItems: [BudgetInsightItem] = []
        var underBudgetItems: [BudgetInsightItem] = []
        for item in budgetItems {
            if item.isOverBudget {
                overBudgetItems.append(item)
            } else if item.projectedSpend > item.budgetAmount {
                projectedOverspendItems.append(item)
            } else if item.percentage < 80 && item.percentage > 0 {
                underBudgetItems.append(item)
            }
        }

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

        let projectedCount = projectedOverspendItems.count
        let underCount = underBudgetItems.count
        PerformanceLogger.InsightsMetrics.logBudgetEnd(insightCount: insights.count, overBudget: overBudgetCount, atRisk: projectedCount, underBudget: underCount)
        Self.logger.debug("💼 [Insights] Budget END — \(insights.count) insights, over=\(overBudgetCount), atRisk=\(projectedCount), under=\(underCount)")
        return insights
    }

    // MARK: - Recurring Insights

    private func generateRecurringInsights(baseCurrency: String, granularity: InsightGranularity? = nil) -> [Insight] {
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

        // Phase 30: Scale to the selected granularity period (weekly/quarterly/yearly equivalent).
        let periodMultiplier: Double
        let periodUnit: String
        switch granularity {
        case .week:
            periodMultiplier = 7.0 / 30.0
            periodUnit       = String(localized: "insights.perWeek")
        case .quarter:
            periodMultiplier = 3.0
            periodUnit       = String(localized: "insights.perQuarter")
        case .year:
            periodMultiplier = 12.0
            periodUnit       = String(localized: "insights.perYear")
        case .month, .allTime, nil:
            periodMultiplier = 1.0
            periodUnit       = String(localized: "insights.perMonth")
        }
        let periodTotal = totalMonthly * periodMultiplier

        PerformanceLogger.InsightsMetrics.logRecurringEnd(totalMonthly: totalMonthly, currency: baseCurrency)
        Self.logger.debug("🔁 [Insights] Recurring END — totalMonthly=\(String(format: "%.0f", totalMonthly), privacy: .public) → periodTotal=\(String(format: "%.0f", periodTotal), privacy: .public) ×\(String(format: "%.2f", periodMultiplier), privacy: .public) \(baseCurrency, privacy: .public)")

        return [Insight(
            id: "total_recurring",
            type: .totalRecurringCost,
            title: granularity?.totalRecurringTitle ?? String(localized: "insights.totalRecurring"),
            subtitle: String(format: String(localized: "insights.activeRecurring"), activeSeries.count),
            metric: InsightMetric(
                value: periodTotal,
                formattedValue: Formatting.formatCurrencySmart(periodTotal, currency: baseCurrency),
                currency: baseCurrency,
                unit: periodUnit
            ),
            trend: nil,
            severity: periodTotal > 0 ? .neutral : .positive,
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
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        let monthlyRecurringNet = self.monthlyRecurringNet(baseCurrency: baseCurrency)
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
        comparisonFilter: TimeFilter? = nil,
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> (subcategories: [SubcategoryBreakdownItem], monthlyTrend: [MonthlyDataPoint], prevBucketTotal: Double) {
        // All category expense transactions (used for prev-bucket comparison)
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

        // Previous-bucket total for period comparison card (Phase 31)
        var prevBucketTotal: Double = 0
        if let cf = comparisonFilter {
            let cfRange = cf.dateRange()
            prevBucketTotal = filterService
                .filterByTimeRange(allCategoryTransactions, start: cfRange.start, end: cfRange.end)
                .reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        }

        return (subcategories, [], prevBucketTotal)
    }

    // MARK: - Granularity-based API (Phase 18, updated Phase 23)

    /// Generates all insights for a given granularity.
    /// Phase 23: accepts pre-built `transactions` array — caller builds it once on MainActor,
    /// avoiding repeated Array(transactionStore.transactions) copies per granularity (P3/P4 fix).
    func generateAllInsights(
        granularity: InsightGranularity,
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        firstTransactionDate: Date? = nil          // hoisted by caller to avoid 5× O(N) re-scan
    ) -> (insights: [Insight], periodPoints: [PeriodDataPoint]) {
        // Determine the date window for this granularity.
        // For .week: last 52 weeks. For .month/.quarter/.year/.allTime: first tx → now (covers all).
        // Use the pre-computed value when provided; fall back to local scan if called standalone.
        let firstDate: Date?
        if let provided = firstTransactionDate {
            firstDate = provided
        } else {
            firstDate = allTransactions
                .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
                .min()
        }
        let (windowStart, windowEnd) = granularity.dateRange(firstTransactionDate: firstDate)

        // Filter transactions to the granularity window so spending / income / budget / savings
        // all respect the selected period. For non-week granularities the window covers every
        // transaction, so this filter is a no-op and performance is unaffected.
        let windowedTransactions = filterService.filterByTimeRange(allTransactions, start: windowStart, end: windowEnd)

        // TimeFilter wrapping the window — passed to generators that use aggregate fetch ranges
        // and the MoM reference date helper.
        let granularityTimeFilter = TimeFilter(preset: .custom, startDate: windowStart, endDate: windowEnd)

        // Period summary scoped to the granularity window
        let (windowedIncome, windowedExpenses) = calculateMonthlySummary(
            transactions: windowedTransactions,
            baseCurrency: baseCurrency,
            currencyService: currencyService
        )
        let periodSummary = PeriodSummary(
            totalIncome: windowedIncome,
            totalExpenses: windowedExpenses,
            netFlow: windowedIncome - windowedExpenses
        )

        // Phase 30: Compute period data points BEFORE generators so spending/income can use
        // granularity-aware bucket comparisons (currentPeriodKey / previousPeriodKey) without
        // duplicate O(N) scans.
        let periodPoints = computePeriodDataPoints(
            transactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            firstTransactionDate: firstDate
        )

        var insights: [Insight] = []

        insights.append(contentsOf: generateSpendingInsights(
            filtered: windowedTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            granularity: granularity,
            periodPoints: periodPoints
        ))

        insights.append(contentsOf: generateIncomeInsights(
            filtered: windowedTransactions,
            allTransactions: allTransactions,
            periodSummary: periodSummary,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            granularity: granularity,
            periodPoints: periodPoints
        ))

        insights.append(contentsOf: generateBudgetInsights(
            transactions: windowedTransactions,
            timeFilter: granularityTimeFilter,
            baseCurrency: baseCurrency
        ))

        insights.append(contentsOf: generateRecurringInsights(baseCurrency: baseCurrency, granularity: granularity))

        insights.append(contentsOf: generateCashFlowInsightsFromPeriodPoints(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor
        ))

        insights.append(contentsOf: generateWealthInsights(
            periodPoints: periodPoints,
            allTransactions: allTransactions,
            granularity: granularity,
            baseCurrency: baseCurrency,
            currencyService: currencyService,
            balanceFor: balanceFor
        ))

        // Phase 24 — Spending stubs
        if let spike = generateSpendingSpike(baseCurrency: baseCurrency) {
            insights.append(spike)
        }
        if let trend = generateCategoryTrend(baseCurrency: baseCurrency) {
            insights.append(trend)
        }

        // Phase 24 — Recurring stub
        if let growth = generateSubscriptionGrowth(baseCurrency: baseCurrency) {
            insights.append(growth)
        }

        // Phase 24 — Savings category (uses windowed income/expenses to respect granularity)
        insights.append(contentsOf: generateSavingsInsights(
            allIncome: windowedIncome,
            allExpenses: windowedExpenses,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor
        ))

        // Phase 31: Narrow incomeSourceBreakdown to current granularity bucket only.
        // This ensures income sources reflect what was earned in the current period, not the full window.
        let currentBucketForForecasting: [Transaction]
        if let cp = periodPoints.first(where: { $0.key == granularity.currentPeriodKey }) {
            currentBucketForForecasting = filterService.filterByTimeRange(
                allTransactions, start: cp.periodStart, end: cp.periodEnd
            )
        } else {
            currentBucketForForecasting = windowedTransactions
        }

        // Phase 24 — Forecasting category
        insights.append(contentsOf: generateForecastingInsights(
            allTransactions: allTransactions,
            baseCurrency: baseCurrency,
            balanceFor: balanceFor,
            filteredTransactions: currentBucketForForecasting
        ))

        // Phase 24 — Behavioral (appended to relevant existing categories)
        if let duplicates = generateDuplicateSubscriptions(baseCurrency: baseCurrency) {
            insights.append(duplicates)
        }
        if let dormancy = generateAccountDormancy(allTransactions: allTransactions, balanceFor: balanceFor) {
            insights.append(dormancy)
        }

        return (insights, periodPoints)
    }

    /// Computes all insight granularities in a single @MainActor call.
    /// Called once from InsightsViewModel.loadInsightsBackground() to replace
    /// the 5-iteration for-loop that caused 5 separate main actor hops.
    func computeAllGranularities(
        transactions allTransactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        firstTransactionDate: Date?
    ) -> [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] {
        var results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])] = [:]
        for gran in InsightGranularity.allCases {
            results[gran] = generateAllInsights(
                granularity: gran,
                transactions: allTransactions,
                baseCurrency: baseCurrency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: balanceFor,
                firstTransactionDate: firstTransactionDate
            )
        }
        return results
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
        let bestPeriod = periodPoints.max(by: { $0.netFlow < $1.netFlow })
        if let best = bestPeriod {
            insights.append(Insight(
                id: "best_month",
                type: .bestMonth,
                title: granularity.bestPeriodTitle,
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

        // 3. Worst period (Phase 24 — complement to Best)
        if let worst = periodPoints.min(by: { $0.netFlow < $1.netFlow }),
           worst.netFlow < 0,
           worst.key != (bestPeriod?.key ?? "") {
            insights.append(Insight(
                id: "worst_month",
                type: .worstMonth,
                title: granularity.worstPeriodTitle,
                subtitle: worst.label,
                metric: InsightMetric(
                    value: worst.netFlow,
                    formattedValue: Formatting.formatCurrencySmart(worst.netFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .warning,
                category: .cashFlow,
                detailData: .periodTrend(periodPoints)
            ))
        }

        // 4. Projected balance (recurring delta scaled to granularity period).
        // Phase 30: multiply monthlyRecurringNet by period factor so the card shows
        // the meaningful recurring impact for the selected granularity.
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        let monthlyRecurringNet = self.monthlyRecurringNet(baseCurrency: baseCurrency)

        let projectedPeriodMultiplier: Double
        let projectedPeriodUnit: String
        switch granularity {
        case .week:
            projectedPeriodMultiplier = 7.0 / 30.0
            projectedPeriodUnit       = String(localized: "insights.perWeek")
        case .quarter:
            projectedPeriodMultiplier = 3.0
            projectedPeriodUnit       = String(localized: "insights.perQuarter")
        case .year:
            projectedPeriodMultiplier = 12.0
            projectedPeriodUnit       = String(localized: "insights.perYear")
        case .month, .allTime:
            projectedPeriodMultiplier = 1.0
            projectedPeriodUnit       = String(localized: "insights.perMonth")
        }
        let periodRecurringNet  = monthlyRecurringNet * projectedPeriodMultiplier
        let projectedBalance    = currentBalance + periodRecurringNet
        let projectedMetricFormatted = periodRecurringNet >= 0
            ? "+" + Formatting.formatCurrencySmart(periodRecurringNet, currency: baseCurrency)
            : Formatting.formatCurrencySmart(periodRecurringNet, currency: baseCurrency)

        insights.append(Insight(
            id: "projected_balance",
            type: .projectedBalance,
            title: String(localized: "insights.projectedBalance"),
            subtitle: projectedPeriodUnit,
            metric: InsightMetric(
                value: periodRecurringNet,
                formattedValue: projectedMetricFormatted,
                currency: baseCurrency,
                unit: projectedPeriodUnit
            ),
            trend: InsightTrend(
                direction: periodRecurringNet >= 0 ? .up : .down,
                changePercent: currentBalance > 0 ? (periodRecurringNet / currentBalance) * 100 : nil,
                changeAbsolute: periodRecurringNet,
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

        var wealthInsights: [Insight] = []

        wealthInsights.append(Insight(
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
        ))

        // Wealth Growth (Phase 24) — period-over-period wealth change
        if let pct = changePercent, abs(pct) > 1 {
            let wealthGrowthSeverity: InsightSeverity = currentPeriodNetFlow > 0 ? .positive : .warning
            wealthInsights.append(Insight(
                id: "wealth_growth",
                type: .wealthGrowth,
                title: String(localized: "insights.wealthGrowth"),
                subtitle: granularity.comparisonPeriodName,
                metric: InsightMetric(
                    value: currentPeriodNetFlow,
                    formattedValue: Formatting.formatCurrencySmart(currentPeriodNetFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: direction,
                    changePercent: pct,
                    changeAbsolute: nil,
                    comparisonPeriod: granularity.comparisonPeriodName
                ),
                severity: wealthGrowthSeverity,
                category: .wealth,
                detailData: .periodTrend(cumulativePoints)
            ))
        }

        return wealthInsights
    }

    // MARK: - Spending Spike (Phase 24)

    /// Detects a category whose current-month spending exceeds 1.5× its 3-month historical average.
    private func generateSpendingSpike(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: startOfMonth(calendar, for: now)) else { return nil }

        let monthlyAggregates = transactionStore.categoryAggregateService.fetchRange(
            from: threeMonthsAgo, to: now, currency: baseCurrency
        )
        guard !monthlyAggregates.isEmpty else { return nil }

        let currentComps = calendar.dateComponents([.year, .month], from: now)
        let currentYear = currentComps.year ?? 0
        let currentMonth = currentComps.month ?? 0

        let byCategory = Dictionary(grouping: monthlyAggregates, by: { $0.categoryName })

        var spikeCategory: String? = nil
        var spikeAmount: Double = 0
        var spikeMultiplier: Double = 1.5 // minimum threshold

        for (catName, records) in byCategory {
            let current = records.first { $0.year == currentYear && $0.month == currentMonth }
            let historical = records.filter { !($0.year == currentYear && $0.month == currentMonth) }
            guard let currentAmount = current?.totalExpenses, currentAmount > 0, !historical.isEmpty else { continue }

            let histAvg = historical.reduce(0.0) { $0 + $1.totalExpenses } / Double(historical.count)
            guard histAvg > 100 else { continue } // ignore tiny amounts

            let multiplier = currentAmount / histAvg
            if multiplier > spikeMultiplier {
                spikeMultiplier = multiplier
                spikeCategory = catName
                spikeAmount = currentAmount
            }
        }

        guard let catName = spikeCategory else { return nil }
        let changePercent = (spikeMultiplier - 1) * 100

        Self.logger.debug("⚡️ [Insights] SpendingSpike — '\(catName, privacy: .public)' ×\(String(format: "%.1f", spikeMultiplier), privacy: .public)")
        return Insight(
            id: "spending_spike",
            type: .spendingSpike,
            title: String(localized: "insights.spendingSpike"),
            subtitle: catName,
            metric: InsightMetric(
                value: spikeAmount,
                formattedValue: Formatting.formatCurrencySmart(spikeAmount, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: .up,
                changePercent: changePercent,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsAverage")
            ),
            severity: spikeMultiplier > 2 ? .critical : .warning,
            category: .spending,
            detailData: nil
        )
    }

    // MARK: - Category Trend (Phase 24)

    /// Finds the expense category that has been rising for the most consecutive months (min 2).
    private func generateCategoryTrend(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: startOfMonth(calendar, for: now)) else { return nil }

        let monthlyAggregates = transactionStore.categoryAggregateService.fetchRange(
            from: sixMonthsAgo, to: now, currency: baseCurrency
        )
        guard monthlyAggregates.count >= 4 else { return nil }

        let byCategory = Dictionary(grouping: monthlyAggregates, by: { $0.categoryName })

        var bestCategory: String? = nil
        var bestStreak = 1 // minimum required streak
        var bestLatestAmount: Double = 0
        var bestChangePercent: Double = 0

        for (catName, records) in byCategory {
            guard records.count >= 3 else { continue }
            let sorted = records.sorted { $0.year != $1.year ? $0.year < $1.year : $0.month < $1.month }

            var streak = 0
            for i in (1..<sorted.count).reversed() {
                if sorted[i].totalExpenses > sorted[i - 1].totalExpenses {
                    streak += 1
                } else {
                    break
                }
            }
            if streak >= 2 && streak > bestStreak {
                bestStreak = streak
                bestCategory = catName
                bestLatestAmount = sorted.last?.totalExpenses ?? 0
                let prevAmount = sorted[max(0, sorted.count - 2)].totalExpenses
                bestChangePercent = prevAmount > 0 ? ((bestLatestAmount - prevAmount) / prevAmount) * 100 : 0
            }
        }

        guard let catName = bestCategory else { return nil }
        Self.logger.debug("📈 [Insights] CategoryTrend — '\(catName, privacy: .public)' rising for \(bestStreak + 1) months")
        return Insight(
            id: "category_trend_\(catName)",
            type: .categoryTrend,
            title: String(localized: "insights.categoryTrend"),
            subtitle: String(format: String(localized: "insights.categoryTrend.risingMonths"), bestStreak + 1),
            metric: InsightMetric(
                value: bestLatestAmount,
                formattedValue: Formatting.formatCurrencySmart(bestLatestAmount, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: .up,
                changePercent: bestChangePercent,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
            ),
            severity: .warning,
            category: .spending,
            detailData: nil
        )
    }

    // MARK: - Subscription Growth (Phase 24)

    /// Compares current monthly recurring total with the total 3 months ago.
    private func generateSubscriptionGrowth(baseCurrency: String) -> Insight? {
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        guard activeSeries.count >= 2 else { return nil }

        let calendar = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else { return nil }

        let dateFormatter = DateFormatters.dateFormatter

        let currentTotal = activeSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }
        let prevSeries = activeSeries.filter { series in
            guard let start = dateFormatter.date(from: series.startDate) else { return false }
            return start < threeMonthsAgo
        }
        let prevTotal = prevSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }

        guard prevTotal > 0, currentTotal > 0 else { return nil }
        let changePercent = ((currentTotal - prevTotal) / prevTotal) * 100
        guard abs(changePercent) > 5 else { return nil }

        let direction: TrendDirection = changePercent > 0 ? .up : .down
        let severity: InsightSeverity = changePercent > 10 ? .warning : (changePercent < -10 ? .positive : .neutral)
        Self.logger.debug("🔁 [Insights] SubscriptionGrowth — \(String(format: "%+.1f%%", changePercent), privacy: .public)")
        return Insight(
            id: "subscription_growth",
            type: .subscriptionGrowth,
            title: String(localized: "insights.subscriptionGrowth"),
            subtitle: String(localized: "insights.vsThreeMonthsAgo"),
            metric: InsightMetric(
                value: currentTotal,
                formattedValue: Formatting.formatCurrencySmart(currentTotal, currency: baseCurrency),
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentTotal - prevTotal,
                comparisonPeriod: String(localized: "insights.vsThreeMonthsAgo")
            ),
            severity: severity,
            category: .recurring,
            detailData: nil
        )
    }

    // MARK: - Savings Insights (Phase 24)

    func generateSavingsInsights(
        allIncome: Double,
        allExpenses: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double
    ) -> [Insight] {
        var insights: [Insight] = []

        if let rate = generateSavingsRate(allIncome: allIncome, allExpenses: allExpenses, baseCurrency: baseCurrency) {
            insights.append(rate)
        }
        if let fund = generateEmergencyFund(baseCurrency: baseCurrency, balanceFor: balanceFor) {
            insights.append(fund)
        }
        if let momentum = generateSavingsMomentum(baseCurrency: baseCurrency) {
            insights.append(momentum)
        }
        return insights
    }

    private func generateSavingsRate(allIncome: Double, allExpenses: Double, baseCurrency: String) -> Insight? {
        guard allIncome > 0 else { return nil }
        let rate = ((allIncome - allExpenses) / allIncome) * 100
        let savedAmount = allIncome - allExpenses
        let severity: InsightSeverity = rate > 20 ? .positive : (rate >= 10 ? .warning : .critical)
        Self.logger.debug("💰 [Insights] SavingsRate — \(String(format: "%.1f%%", rate), privacy: .public), severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "savings_rate",
            type: .savingsRate,
            title: String(localized: "insights.savingsRate"),
            subtitle: Formatting.formatCurrencySmart(max(0, savedAmount), currency: baseCurrency),
            metric: InsightMetric(
                value: rate,
                formattedValue: String(format: "%.1f%%", rate),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }

    private func generateEmergencyFund(baseCurrency: String, balanceFor: (String) -> Double) -> Insight? {
        let totalBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard totalBalance > 0 else { return nil }

        let aggregates = transactionStore.monthlyAggregateService.fetchLast(3, currency: baseCurrency)
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyExpenses = aggregates.reduce(0.0) { $0 + $1.totalExpenses } / Double(aggregates.count)
        guard avgMonthlyExpenses > 0 else { return nil }

        let monthsCovered = totalBalance / avgMonthlyExpenses
        let severity: InsightSeverity = monthsCovered >= 3 ? .positive : (monthsCovered >= 1 ? .warning : .critical)
        let monthsInt = Int(monthsCovered.rounded(.down))
        Self.logger.debug("🛡 [Insights] EmergencyFund — \(String(format: "%.1f", monthsCovered), privacy: .public) months, severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "emergency_fund",
            type: .emergencyFund,
            title: String(localized: "insights.emergencyFund"),
            subtitle: String(format: String(localized: "insights.monthsCovered"), monthsInt),
            metric: InsightMetric(
                value: monthsCovered,
                formattedValue: String(format: "%.1f", monthsCovered),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }

    private func generateSavingsMomentum(baseCurrency: String) -> Insight? {
        let aggregates = transactionStore.monthlyAggregateService.fetchLast(4, currency: baseCurrency)
        guard aggregates.count >= 2 else { return nil }

        let rates: [Double] = aggregates.map { agg in
            guard agg.totalIncome > 0 else { return 0 }
            return ((agg.totalIncome - agg.totalExpenses) / agg.totalIncome) * 100
        }

        guard let currentRate = rates.last else { return nil }
        let prevRates = Array(rates.dropLast())
        guard !prevRates.isEmpty else { return nil }

        let avgPrevRate = prevRates.reduce(0.0, +) / Double(prevRates.count)
        let delta = currentRate - avgPrevRate
        guard abs(delta) > 1 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta > 2 ? .positive : (delta < -2 ? .warning : .neutral)
        Self.logger.debug("📊 [Insights] SavingsMomentum — current=\(String(format: "%.1f%%", currentRate), privacy: .public), avgPrev=\(String(format: "%.1f%%", avgPrevRate), privacy: .public), delta=\(String(format: "%+.1f%%", delta), privacy: .public)")
        return Insight(
            id: "savings_momentum",
            type: .savingsMomentum,
            title: String(localized: "insights.savingsMomentum"),
            subtitle: String(localized: "insights.vsPrevious3Months"),
            metric: InsightMetric(
                value: currentRate,
                formattedValue: String(format: "%.1f%%", currentRate),
                currency: nil,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: delta,
                changeAbsolute: nil,
                comparisonPeriod: String(localized: "insights.vsPrevious3Months")
            ),
            severity: severity,
            category: .savings,
            detailData: nil
        )
    }

    // MARK: - Forecasting Insights (Phase 24)

    func generateForecastingInsights(
        allTransactions: [Transaction],
        baseCurrency: String,
        balanceFor: (String) -> Double,
        filteredTransactions: [Transaction]? = nil
    ) -> [Insight] {
        var insights: [Insight] = []

        if let forecast = generateSpendingForecast(baseCurrency: baseCurrency) {
            insights.append(forecast)
        }
        if let runway = generateBalanceRunway(baseCurrency: baseCurrency, balanceFor: balanceFor) {
            insights.append(runway)
        }
        if let yoy = generateYearOverYear(baseCurrency: baseCurrency) {
            insights.append(yoy)
        }
        if let seasonality = generateIncomeSeasonality(baseCurrency: baseCurrency) {
            insights.append(seasonality)
        }
        if let velocity = generateSpendingVelocity(baseCurrency: baseCurrency) {
            insights.append(velocity)
        }
        // Phase 30: use filteredTransactions (windowed) when available so incomeSourceBreakdown
        // respects the selected granularity period.
        let sourceTransactions = filteredTransactions ?? allTransactions
        if let breakdown = generateIncomeSourceBreakdown(allTransactions: sourceTransactions, baseCurrency: baseCurrency) {
            insights.append(breakdown)
        }
        return insights
    }

    /// Projects month-end spend = avg daily rate × remaining days + pending recurring.
    private func generateSpendingForecast(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = startOfMonth(calendar, for: now)

        // Avg daily spend from last 30 days
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let last30Aggregates = transactionStore.categoryAggregateService.fetchRange(
            from: thirtyDaysAgo, to: now, currency: baseCurrency
        )
        let last30Spent = last30Aggregates.reduce(0.0) { $0 + $1.totalExpenses }
        let avgDailySpend = last30Spent / 30

        // Days remaining this month
        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: now)
        let daysRemaining = totalDaysInMonth - dayOfMonth

        // Pending recurring this month
        let monthlyRecurringExpenses = transactionStore.recurringSeries
            .filter { $0.isActive }
            .filter { series in
                let isExpense = transactionStore.categories.first { c in c.name == series.category }?.type != .income
                return isExpense
            }
            .reduce(0.0) { total, series in
                // Only count remaining occurrences this month
                let dateFormatter = DateFormatters.dateFormatter
                guard let startDate = dateFormatter.date(from: series.startDate) else { return total }
                // Include if series started before or during this month
                if startDate > now { return total }
                return total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency)
            }

        let spentSoFar = transactionStore.monthlyAggregateService
            .fetchLast(1, currency: baseCurrency)
            .first?.totalExpenses ?? 0

        let pendingRecurring = max(0, (monthlyRecurringExpenses / Double(totalDaysInMonth)) * Double(daysRemaining))
        let forecast = spentSoFar + (avgDailySpend * Double(daysRemaining)) + pendingRecurring

        let monthlyIncome = transactionStore.monthlyAggregateService
            .fetchLast(1, currency: baseCurrency)
            .first?.totalIncome ?? 0

        let severity: InsightSeverity = monthlyIncome > 0 ? (forecast > monthlyIncome ? .warning : .positive) : .neutral
        _ = monthStart // suppress unused warning

        Self.logger.debug("🔮 [Insights] SpendingForecast — spentSoFar=\(String(format: "%.0f", spentSoFar), privacy: .public), avgDaily=\(String(format: "%.0f", avgDailySpend), privacy: .public), daysLeft=\(daysRemaining), forecast=\(String(format: "%.0f", forecast), privacy: .public) \(baseCurrency, privacy: .public)")
        return Insight(
            id: "spending_forecast",
            type: .spendingForecast,
            title: String(localized: "insights.spendingForecast"),
            subtitle: String(format: "%d " + String(localized: "insights.days") + " " + String(localized: "insights.remaining"), daysRemaining),
            metric: InsightMetric(
                value: forecast,
                formattedValue: Formatting.formatCurrencySmart(forecast, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// How many months the current balance will last at the current net-burn rate.
    private func generateBalanceRunway(baseCurrency: String, balanceFor: (String) -> Double) -> Insight? {
        let currentBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard currentBalance > 0 else { return nil }

        let aggregates = transactionStore.monthlyAggregateService.fetchLast(3, currency: baseCurrency)
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyNetFlow = aggregates.reduce(0.0) { $0 + $1.netFlow } / Double(aggregates.count)

        if avgMonthlyNetFlow > 0 {
            // Positive net: show how much being saved monthly
            return Insight(
                id: "balance_runway",
                type: .balanceRunway,
                title: String(localized: "insights.balanceRunway"),
                subtitle: Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency) + " " + String(localized: "insights.perMonth"),
                metric: InsightMetric(
                    value: avgMonthlyNetFlow,
                    formattedValue: "+" + Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: String(localized: "insights.perMonth")
                ),
                trend: nil,
                severity: .positive,
                category: .forecasting,
                detailData: nil
            )
        }

        let runway = currentBalance / abs(avgMonthlyNetFlow)
        let severity: InsightSeverity = runway >= 3 ? .positive : (runway >= 1 ? .warning : .critical)
        Self.logger.debug("🛤 [Insights] BalanceRunway — balance=\(String(format: "%.0f", currentBalance), privacy: .public), burn=\(String(format: "%.0f", avgMonthlyNetFlow), privacy: .public)/mo, runway=\(String(format: "%.1f", runway), privacy: .public) months")
        return Insight(
            id: "balance_runway",
            type: .balanceRunway,
            title: String(localized: "insights.balanceRunway"),
            subtitle: String(format: "%.1f " + String(localized: "insights.balanceRunway.months"), runway),
            metric: InsightMetric(
                value: runway,
                formattedValue: String(format: "%.1f", runway),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Compares this month's expenses against the same month last year.
    private func generateYearOverYear(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }

        let thisMonth = transactionStore.monthlyAggregateService
            .fetchLast(1, currency: baseCurrency)
            .first

        let lastYear = transactionStore.monthlyAggregateService
            .fetchLast(1, anchor: oneYearAgo, currency: baseCurrency)
            .first

        guard let thisExpenses = thisMonth?.totalExpenses,
              let lastYearExpenses = lastYear?.totalExpenses,
              lastYearExpenses > 0 else { return nil }

        let delta = ((thisExpenses - lastYearExpenses) / lastYearExpenses) * 100
        guard abs(delta) > 3 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta <= -10 ? .positive : (delta >= 15 ? .warning : .neutral)
        let thisLabel = thisMonth?.label ?? ""
        Self.logger.debug("📅 [Insights] YoY — this=\(String(format: "%.0f", thisExpenses), privacy: .public), lastYear=\(String(format: "%.0f", lastYearExpenses), privacy: .public), delta=\(String(format: "%+.1f%%", delta), privacy: .public)")
        return Insight(
            id: "year_over_year",
            type: .yearOverYear,
            title: String(localized: "insights.yearOverYear"),
            subtitle: thisLabel,
            metric: InsightMetric(
                value: thisExpenses,
                formattedValue: Formatting.formatCurrencySmart(thisExpenses, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: delta,
                changeAbsolute: thisExpenses - lastYearExpenses,
                comparisonPeriod: String(localized: "insights.yearOverYear")
            ),
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Identifies which calendar month historically generates the highest income.
    private func generateIncomeSeasonality(baseCurrency: String) -> Insight? {
        // Fetch all-time monthly aggregates
        let calendar = Calendar.current
        let now = Date()
        guard let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now) else { return nil }

        let allAggregates = transactionStore.monthlyAggregateService.fetchRange(
            from: fiveYearsAgo, to: now, currency: baseCurrency
        )
        guard allAggregates.count >= 12 else { return nil }

        // Group by calendar month (1-12) and compute average income per month
        var incomeByMonth = [Int: [Double]]()
        for agg in allAggregates where agg.totalIncome > 0 {
            incomeByMonth[agg.month, default: []].append(agg.totalIncome)
        }
        guard incomeByMonth.count >= 6 else { return nil }

        let avgByMonth: [(month: Int, avg: Double)] = incomeByMonth.map { month, incomes in
            (month: month, avg: incomes.reduce(0, +) / Double(incomes.count))
        }
        let overallAvg = avgByMonth.reduce(0.0) { $0 + $1.avg } / Double(avgByMonth.count)
        guard overallAvg > 0 else { return nil }

        guard let peak = avgByMonth.max(by: { $0.avg < $1.avg }) else { return nil }
        let peakPercent = ((peak.avg - overallAvg) / overallAvg) * 100
        guard peakPercent > 10 else { return nil }

        // Get month name
        let monthDate = calendar.date(from: DateComponents(year: 2024, month: peak.month, day: 1)) ?? now
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        monthFormatter.locale = .current
        let monthName = monthFormatter.string(from: monthDate)

        Self.logger.debug("🌊 [Insights] IncomeSeasonality — peak month \(peak.month) (\(monthName, privacy: .public)), +\(String(format: "%.0f%%", peakPercent), privacy: .public) above avg")
        return Insight(
            id: "income_seasonality",
            type: .incomeSeasonality,
            title: String(localized: "insights.incomeSeasonality"),
            subtitle: monthName,
            metric: InsightMetric(
                value: peakPercent,
                formattedValue: String(format: "+%.0f%%", peakPercent),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Compares current daily spending rate vs last month's daily rate.
    private func generateSpendingVelocity(baseCurrency: String) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let dayOfMonth = calendar.component(.day, from: now)
        guard dayOfMonth > 3 else { return nil } // need a few days of data

        let thisMonth = transactionStore.monthlyAggregateService.fetchLast(1, currency: baseCurrency).first
        let lastMonth = transactionStore.monthlyAggregateService.fetchLast(2, currency: baseCurrency).first

        guard let spentSoFar = thisMonth?.totalExpenses, spentSoFar > 0 else { return nil }
        guard let lastMonthTotal = lastMonth?.totalExpenses, lastMonthTotal > 0 else { return nil }

        let currentDailyRate = spentSoFar / Double(dayOfMonth)

        // Last month days
        guard let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let lastMonthDays = Double(calendar.range(of: .day, in: .month, for: prevMonthDate)?.count ?? 30)
        let lastMonthDailyRate = lastMonthTotal / lastMonthDays

        let ratio = currentDailyRate / lastMonthDailyRate
        guard abs(ratio - 1.0) > 0.1 else { return nil } // only show if >10% difference

        let changePercent = (ratio - 1.0) * 100
        let direction: TrendDirection = ratio > 1 ? .up : .down
        let severity: InsightSeverity = ratio > 1.3 ? .warning : (ratio < 0.8 ? .positive : .neutral)

        Self.logger.debug("⏱ [Insights] SpendingVelocity — ratio=\(String(format: "%.2f", ratio), privacy: .public)x, change=\(String(format: "%+.1f%%", changePercent), privacy: .public)")
        return Insight(
            id: "spending_velocity",
            type: .spendingVelocity,
            title: String(localized: "insights.spendingVelocity"),
            subtitle: String(format: "%+.0f%%", changePercent),
            metric: InsightMetric(
                value: ratio,
                formattedValue: String(format: "%.1fx", ratio),
                currency: nil,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentDailyRate - lastMonthDailyRate,
                comparisonPeriod: String(localized: "insights.vsPreviousPeriod")
            ),
            severity: severity,
            category: .forecasting,
            detailData: nil
        )
    }

    /// Groups income transactions by category to show income source distribution.
    private func generateIncomeSourceBreakdown(allTransactions: [Transaction], baseCurrency: String) -> Insight? {
        let incomeCategories = transactionStore.categories.filter { $0.type == .income }
        guard incomeCategories.count >= 2 else { return nil }

        let incomeTransactions = allTransactions.filter { $0.type == .income }
        guard !incomeTransactions.isEmpty else { return nil }

        let totalIncome = incomeTransactions.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
        guard totalIncome > 0 else { return nil }

        let grouped = Dictionary(grouping: incomeTransactions, by: { $0.category })
        let breakdownItems: [CategoryBreakdownItem] = grouped
            .map { catName, txns -> CategoryBreakdownItem in
                let amount = txns.reduce(0.0) { $0 + resolveAmount($1, baseCurrency: baseCurrency) }
                let pct = (amount / totalIncome) * 100
                let cat = transactionStore.categories.first { $0.name == catName }
                return CategoryBreakdownItem(
                    id: catName,
                    categoryName: catName,
                    amount: amount,
                    percentage: pct,
                    color: Color(hex: cat?.colorHex ?? "#5856D6"),
                    iconSource: cat?.iconSource,
                    subcategories: []
                )
            }
            .sorted { $0.amount > $1.amount }

        guard let top = breakdownItems.first else { return nil }
        let topPercent = top.percentage

        Self.logger.debug("💼 [Insights] IncomeSourceBreakdown — \(breakdownItems.count) sources, top='\(top.categoryName, privacy: .public)' \(String(format: "%.0f%%", topPercent), privacy: .public)")
        return Insight(
            id: "income_source_breakdown",
            type: .incomeSourceBreakdown,
            title: String(localized: "insights.incomeSourceBreakdown"),
            subtitle: top.categoryName,
            metric: InsightMetric(
                value: topPercent,
                formattedValue: String(format: "%.0f%%", topPercent),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .income,
            detailData: .categoryBreakdown(breakdownItems)
        )
    }

    // MARK: - Private Helper: Monthly Equivalent

    /// Converts a recurring series amount to monthly equivalent in baseCurrency.
    private func seriesMonthlyEquivalent(_ series: RecurringSeries, baseCurrency: String) -> Double {
        let amount = NSDecimalNumber(decimal: series.amount).doubleValue
        let rawMonthly: Double
        switch series.frequency {
        case .daily:   rawMonthly = amount * 30
        case .weekly:  rawMonthly = amount * 4.33
        case .monthly: rawMonthly = amount
        case .yearly:  rawMonthly = amount / 12
        }
        if series.currency != baseCurrency,
           let converted = CurrencyConverter.convertSync(amount: rawMonthly, from: series.currency, to: baseCurrency) {
            return converted
        }
        return rawMonthly
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

    // MARK: - Financial Health Score (Phase 24)

    /// Computes a composite 0-100 financial health score from five weighted components.
    /// Call after `generateAllInsights` once totals and period data points are available.
    func computeHealthScore(
        totalIncome: Double,
        totalExpenses: Double,
        latestNetFlow: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double
    ) -> FinancialHealthScore {
        guard totalIncome > 0 else { return .unavailable() }

        let calendar = Calendar.current
        let now = Date()

        // --- Component 1: Savings Rate (weight 0.30) ---
        let savingsRate = (totalIncome - totalExpenses) / totalIncome * 100
        let savingsRateScore = Int(min(savingsRate / 20.0 * 100, 100).rounded())

        // --- Component 2: Budget Adherence (weight 0.25) ---
        let monthStart = startOfMonth(calendar, for: now)
        let currentMonthAggregates = transactionStore.categoryAggregateService.fetchRange(
            from: monthStart, to: now, currency: baseCurrency
        )
        let categoriesWithBudget = transactionStore.categories.filter { ($0.budgetAmount ?? 0) > 0 }
        let onBudgetCount = categoriesWithBudget.filter { category in
            let spent = currentMonthAggregates.first { $0.categoryName == category.name }?.totalExpenses ?? 0
            return spent <= (category.budgetAmount ?? 0)
        }.count
        let totalBudgetCount = categoriesWithBudget.count
        let budgetAdherenceScore = totalBudgetCount > 0
            ? Int((Double(onBudgetCount) / Double(totalBudgetCount) * 100).rounded())
            : 50 // neutral when no budgets set

        // --- Component 3: Recurring Ratio (weight 0.20) ---
        let recurringCost = transactionStore.recurringSeries
            .filter { $0.isActive }
            .reduce(0.0) { total, series in
                let isExpense = transactionStore.categories.first { $0.name == series.category }?.type != .income
                return isExpense ? total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency) : total
            }
        let recurringRatioScore = Int(max(0, (1.0 - recurringCost / max(totalIncome, 1)) * 100).rounded())

        // --- Component 4: Emergency Fund (weight 0.15) ---
        let totalBalance = transactionStore.accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        let last3Months = transactionStore.monthlyAggregateService.fetchLast(3, anchor: now, currency: baseCurrency)
        let avgMonthlyExpenses = last3Months.isEmpty
            ? totalExpenses / 12
            : last3Months.reduce(0.0) { $0 + $1.totalExpenses } / Double(last3Months.count)
        let monthsCovered = avgMonthlyExpenses > 0 ? totalBalance / avgMonthlyExpenses : 0
        let emergencyFundScore = Int(min(monthsCovered / 6.0 * 100, 100).rounded())

        // --- Component 5: Cash Flow (weight 0.10) ---
        let cashflowScore = latestNetFlow > 0 ? 100 : 0

        // --- Weighted Total ---
        let total = Double(savingsRateScore)     * 0.30
                  + Double(budgetAdherenceScore) * 0.25
                  + Double(recurringRatioScore)  * 0.20
                  + Double(emergencyFundScore)   * 0.15
                  + Double(cashflowScore)        * 0.10
        let score = Int(total.rounded())

        let (grade, gradeColor): (String, Color)
        switch score {
        case 80...100: (grade, gradeColor) = (String(localized: "insights.healthGrade.excellent"),     AppColors.success)
        case 60..<80:  (grade, gradeColor) = (String(localized: "insights.healthGrade.good"),          AppColors.accent)
        case 40..<60:  (grade, gradeColor) = (String(localized: "insights.healthGrade.fair"),          AppColors.warning)
        default:       (grade, gradeColor) = (String(localized: "insights.healthGrade.needsAttention"), AppColors.destructive)
        }

        return FinancialHealthScore(
            score: score,
            grade: grade,
            gradeColor: gradeColor,
            savingsRateScore:     max(0, min(savingsRateScore, 100)),
            budgetAdherenceScore: max(0, min(budgetAdherenceScore, 100)),
            recurringRatioScore:  max(0, min(recurringRatioScore, 100)),
            emergencyFundScore:   max(0, min(emergencyFundScore, 100)),
            cashflowScore:        cashflowScore
        )
    }

    // MARK: - Behavioral Insights (Phase 24)

    /// Detects possible duplicate subscriptions — active series with the same category
    /// OR monthly cost within 15% of each other.
    private func generateDuplicateSubscriptions(baseCurrency: String) -> Insight? {
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive && $0.kind == .subscription }
        guard activeSeries.count >= 2 else { return nil }

        // Group by category; flag categories with 2+ subscriptions
        let grouped = Dictionary(grouping: activeSeries, by: \.category)
        let duplicateGroups = grouped.filter { $0.value.count >= 2 }
        guard !duplicateGroups.isEmpty else {
            // Secondary check: any two subscriptions with monthly cost within 15%
            let costs = activeSeries.map { seriesMonthlyEquivalent($0, baseCurrency: baseCurrency) }.sorted()
            var hasSimilarCost = false
            for i in 0..<costs.count - 1 {
                let a = costs[i]; let b = costs[i + 1]
                guard a > 0 else { continue }
                if abs(a - b) / a < 0.15 { hasSimilarCost = true; break }
            }
            guard hasSimilarCost else { return nil }

            let totalDuplicateCost = costs.dropFirst().reduce(0, +) // rough estimate
            return Insight(
                id: "duplicateSubscriptions",
                type: .duplicateSubscriptions,
                title: String(localized: "insights.duplicateSubscriptions.title"),
                subtitle: String(localized: "insights.duplicateSubscriptions.subtitle"),
                metric: InsightMetric(
                    value: totalDuplicateCost,
                    formattedValue: Formatting.formatCurrency(totalDuplicateCost, currency: baseCurrency),
                    currency: baseCurrency, unit: nil
                ),
                trend: nil,
                severity: .warning,
                category: .recurring,
                detailData: nil
            )
        }

        let duplicateCount = duplicateGroups.values.reduce(0) { $0 + $1.count }
        let duplicateCost = duplicateGroups.values.flatMap { $0 }
            .reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }
        return Insight(
            id: "duplicateSubscriptions",
            type: .duplicateSubscriptions,
            title: String(localized: "insights.duplicateSubscriptions.title"),
            subtitle: "\(duplicateCount) \(String(localized: "insights.duplicateSubscriptions.subtitle"))",
            metric: InsightMetric(
                value: duplicateCost,
                formattedValue: Formatting.formatCurrency(duplicateCost, currency: baseCurrency),
                currency: baseCurrency, unit: nil
            ),
            trend: nil,
            severity: .warning,
            category: .recurring,
            detailData: nil
        )
    }

    /// Flags accounts that have been idle for 30+ days but still hold a positive balance.
    private func generateAccountDormancy(allTransactions: [Transaction], balanceFor: (String) -> Double) -> Insight? {
        let dateFormatter = DateFormatters.dateFormatter
        let now = Date()
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return nil }

        let dormantAccounts: [AccountInsightItem] = transactionStore.accounts.compactMap { account in
            let balance = balanceFor(account.id)
            guard balance > 0 else { return nil }
            let lastTx = allTransactions
                .filter { $0.accountId == account.id }
                .compactMap { dateFormatter.date(from: $0.date) }
                .max()
            guard let last = lastTx, last < thirtyDaysAgo else { return nil }
            return AccountInsightItem(
                id: account.id,
                accountName: account.name,
                currency: account.currency,
                balance: balance,
                transactionCount: 0,
                lastActivityDate: last,
                iconSource: account.iconSource
            )
        }
        guard !dormantAccounts.isEmpty else { return nil }

        let totalDormantBalance = dormantAccounts.reduce(0.0) { $0 + $1.balance }
        return Insight(
            id: "accountDormancy",
            type: .accountDormancy,
            title: String(localized: "insights.accountDormancy.title"),
            subtitle: "\(dormantAccounts.count) \(String(localized: "insights.accountDormancy.subtitle"))",
            metric: InsightMetric(
                value: Double(dormantAccounts.count),
                formattedValue: "\(dormantAccounts.count)",
                currency: nil, unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .wealth,
            detailData: .accountComparison(dormantAccounts)
        )
    }

    /// Phase 23-C P12: shared monthly recurring net calculation.
    /// Was duplicated verbatim in generateCashFlowInsights and generateCashFlowInsightsFromPeriodPoints.
    private func monthlyRecurringNet(baseCurrency: String) -> Double {
        let activeSeries = transactionStore.recurringSeries.filter { $0.isActive }
        return activeSeries.reduce(0.0) { total, series in
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
    }
}
