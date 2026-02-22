//
//  InsightsViewModel.swift
//  AIFinanceManager
//
//  Phase 23: Insights Performance & UI fixes
//  - 23-A: All heavy computation offloaded to background thread via Task.detached
//  - Eliminated UI freezes on first tab open (loadInsightsForeground blocked MainActor)
//  - Single Array copy of transactions per cycle — not per granularity (P4 fix)
//  - makeBalanceSnapshot() captures balances on MainActor before background hop
//  - Only the final UI write hops back via await MainActor.run
//

import Foundation
import SwiftUI
import Observation
import os

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - Logger

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsViewModel")

    // MARK: - Dependencies

    private let insightsService: InsightsService
    private let transactionStore: TransactionStore
    private let transactionsViewModel: TransactionsViewModel

    // MARK: - Push-model cache

    /// Pre-computed insights keyed by granularity.
    /// Populated in background when data changes; read instantly on tab open.
    private var precomputedInsights: [InsightGranularity: [Insight]] = [:]

    /// Pre-computed period data points keyed by granularity.
    private var precomputedPeriodPoints: [InsightGranularity: [PeriodDataPoint]] = [:]

    /// Pre-computed period totals keyed by granularity.
    private struct PeriodTotals {
        let income: Double
        let expenses: Double
        let netFlow: Double
    }
    private var precomputedTotals: [InsightGranularity: PeriodTotals] = [:]

    /// Background recompute task handle — cancelled and replaced on each data change.
    private var recomputeTask: Task<Void, Never>?

    /// Phase 18: Stale flag — when true, data needs recompute on next onAppear
    private var isStale: Bool = true

    // MARK: - Observable State

    private(set) var insights: [Insight] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var selectedCategory: InsightCategory? = nil
    private(set) var periodDataPoints: [PeriodDataPoint] = []
    private(set) var totalIncome: Double = 0
    private(set) var totalExpenses: Double = 0
    private(set) var netFlow: Double = 0
    /// Phase 24 — Financial Health Score (computed once per recompute cycle, using .month granularity data)
    private(set) var healthScore: FinancialHealthScore? = nil

    // MARK: - Granularity (replaces TimeFilter for Insights)

    private(set) var currentGranularity: InsightGranularity = .month

    /// Legacy: kept for CategoryDeepDive compatibility until it is migrated to granularity.
    private(set) var currentTimeFilter: TimeFilter = TimeFilter(preset: .allTime)

    // MARK: - Computed Properties

    var filteredInsights: [Insight] {
        guard let category = selectedCategory else { return insights }
        return insights.filter { $0.category == category }
    }

    var spendingInsights: [Insight]     { insights.filter { $0.category == .spending } }
    var incomeInsights: [Insight]       { insights.filter { $0.category == .income } }
    var budgetInsights: [Insight]       { insights.filter { $0.category == .budget } }
    var recurringInsights: [Insight]    { insights.filter { $0.category == .recurring } }
    var cashFlowInsights: [Insight]     { insights.filter { $0.category == .cashFlow } }
    var wealthInsights: [Insight]       { insights.filter { $0.category == .wealth } }
    var savingsInsights: [Insight]      { insights.filter { $0.category == .savings } }     // Phase 24
    var forecastingInsights: [Insight]  { insights.filter { $0.category == .forecasting } } // Phase 24

    var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    var hasData: Bool {
        !transactionStore.transactions.isEmpty
    }

    // MARK: - Init

    init(
        insightsService: InsightsService,
        transactionStore: TransactionStore,
        transactionsViewModel: TransactionsViewModel
    ) {
        self.insightsService = insightsService
        self.transactionStore = transactionStore
        self.transactionsViewModel = transactionsViewModel
    }

    // MARK: - Public Methods

    /// Called when the user switches granularity (instant — reads precomputed data).
    func switchGranularity(_ granularity: InsightGranularity) {
        guard granularity != currentGranularity else { return }
        currentGranularity = granularity
        Self.logger.debug("🧠 [InsightsVM] switchGranularity → \(granularity.rawValue, privacy: .public)")
        applyPrecomputed(for: granularity)
    }

    /// Called when Insights tab appears — triggers computation if stale.
    /// When data is fresh, reads from precomputed cache (0ms).
    func onAppear() {
        if isStale || precomputedInsights[currentGranularity] == nil {
            Self.logger.debug("🧠 [InsightsVM] onAppear — stale or cache MISS, loading")
            isStale = false
            loadInsightsBackground()
        } else {
            Self.logger.debug("🧠 [InsightsVM] onAppear — cache HIT (instant)")
            applyPrecomputed(for: currentGranularity)
        }
    }

    /// Lazy invalidation — marks stale without eager recompute.
    /// Computation is deferred until user opens the Insights tab.
    func invalidateAndRecompute() {
        Self.logger.debug("🔄 [InsightsVM] invalidateAndRecompute — marking stale (lazy)")
        insightsService.invalidateCache()
        precomputedInsights = [:]
        precomputedPeriodPoints = [:]
        precomputedTotals = [:]
        isStale = true
        recomputeTask?.cancel()
    }

    func invalidateCache() {
        invalidateAndRecompute()
    }

    func refreshInsights() {
        Self.logger.debug("🔄 [InsightsVM] refreshInsights — manual refresh")
        PerformanceLogger.shared.reset()
        invalidateAndRecompute()
        loadInsightsBackground()
    }

    func selectCategory(_ category: InsightCategory?) {
        selectedCategory = category
    }

    // MARK: - Category Deep Dive

    func categoryDeepDive(
        categoryName: String
    ) -> (subcategories: [SubcategoryBreakdownItem], monthlyTrend: [MonthlyDataPoint], prevBucketTotal: Double) {
        let allTransactions = Array(transactionStore.transactions)

        // Phase 31: Use current granularity bucket only (not the full window).
        let currentKey   = currentGranularity.currentPeriodKey
        let currentStart = currentGranularity.periodStart(for: currentKey)
        let currentEnd   = currentGranularity.periodEnd(for: currentKey)
        let currentFilter = TimeFilter(preset: .custom, startDate: currentStart, endDate: currentEnd)

        // Previous bucket — for the comparison card in CategoryDeepDiveView.
        let prevKey   = currentGranularity.previousPeriodKey
        let prevStart = currentGranularity.periodStart(for: prevKey)
        let prevEnd   = currentStart   // prev bucket ends where current bucket begins
        let prevFilter = TimeFilter(preset: .custom, startDate: prevStart, endDate: prevEnd)

        return insightsService.generateCategoryDeepDive(
            categoryName: categoryName,
            allTransactions: allTransactions,
            timeFilter: currentFilter,
            comparisonFilter: prevFilter,
            baseCurrency: baseCurrency,
            cacheManager: transactionsViewModel.cacheManager,
            currencyService: transactionsViewModel.currencyService
        )
    }

    // MARK: - Private: Background Loading

    /// Phase 23-A: Offloads ALL computation to a detached background task.
    /// Values needed for computation are captured on MainActor before the hop.
    /// Only the final UI write returns to MainActor via await MainActor.run { }.
    private func loadInsightsBackground() {
        isLoading = true
        recomputeTask?.cancel()

        // Capture everything needed on the background thread while on MainActor
        let currency = baseCurrency
        let cacheManager = transactionsViewModel.cacheManager
        let currencyService = transactionsViewModel.currencyService
        let service = insightsService
        // Single Array copy for the entire recompute — not per-granularity (P4 fix)
        let allTransactions = Array(transactionStore.transactions)
        // Balance snapshot: captures account balances safely before leaving MainActor
        let balanceSnapshot = makeBalanceSnapshot()
        let granularity = currentGranularity

        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            Self.logger.debug("🔧 [InsightsVM] Background recompute START (detached) — \(InsightGranularity.allCases.count) granularities")

            let firstDate = allTransactions
                .compactMap { DateFormatters.dateFormatter.date(from: $0.date) }
                .min()

            var newInsights = [InsightGranularity: [Insight]]()
            var newPoints   = [InsightGranularity: [PeriodDataPoint]]()
            var newTotals   = [InsightGranularity: PeriodTotals]()

            for gran in InsightGranularity.allCases {
                guard !Task.isCancelled else { break }

                // Phase 30: generateAllInsights returns (insights, periodPoints) tuple —
                // periodPoints are computed INSIDE the call (before generators), so no
                // separate computePeriodDataPoints call is needed here.
                let result = await service.generateAllInsights(
                    granularity: gran,
                    transactions: allTransactions,
                    baseCurrency: currency,
                    cacheManager: cacheManager,
                    currencyService: currencyService,
                    balanceFor: { balanceSnapshot[$0] ?? 0 },
                    firstTransactionDate: firstDate   // pre-computed once before loop — avoids 5× O(N) re-scan
                )

                let points = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in points { income += p.income; expenses += p.expenses }

                newInsights[gran] = result.insights
                newPoints[gran]   = points
                newTotals[gran]   = PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(points.count) pts")
            }

            guard !Task.isCancelled else { return }

            // Phase 24: Compute health score once using .month granularity totals + period data
            let monthTotals  = newTotals[.month]
            let monthPoints  = newPoints[.month] ?? []
            let latestNetFlow = monthPoints.last?.netFlow ?? 0
            let computedHealthScore = await service.computeHealthScore(
                totalIncome: monthTotals?.income   ?? 0,
                totalExpenses: monthTotals?.expenses ?? 0,
                latestNetFlow: latestNetFlow,
                baseCurrency: currency,
                balanceFor: { balanceSnapshot[$0] ?? 0 }
            )

            // Hop back to MainActor only for the UI write.
            // Use self.currentGranularity (not the captured `granularity`) so that if the user
            // switched granularity while the background task was running, we show the correct data.
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.precomputedInsights    = newInsights
                self.precomputedPeriodPoints = newPoints
                self.precomputedTotals      = newTotals
                self.healthScore            = computedHealthScore
                self.applyPrecomputed(for: self.currentGranularity)
                Self.logger.debug("🔧 [InsightsVM] Background recompute END — UI updated for .\(self.currentGranularity.rawValue, privacy: .public)")
            }
        }
    }

    /// Applies precomputed data for the given granularity to observable properties.
    private func applyPrecomputed(for granularity: InsightGranularity) {
        insights       = precomputedInsights[granularity] ?? []
        periodDataPoints = precomputedPeriodPoints[granularity] ?? []
        let totals     = precomputedTotals[granularity]
        totalIncome    = totals?.income   ?? 0
        totalExpenses  = totals?.expenses ?? 0
        netFlow        = totals?.netFlow  ?? 0
        isLoading = false
    }

    /// Captures a snapshot of account balances on MainActor for safe use on background thread.
    private func makeBalanceSnapshot() -> [String: Double] {
        var snapshot = [String: Double]()
        snapshot.reserveCapacity(transactionStore.accounts.count)
        for account in transactionStore.accounts {
            snapshot[account.id] = transactionsViewModel.calculateTransactionsBalance(for: account.id)
        }
        return snapshot
    }

    // MARK: - Legacy loadInsights

    /// Backward-compatible bridge: converts TimeFilter preset to InsightGranularity.
    func loadInsights(timeFilter: TimeFilter) {
        currentTimeFilter = timeFilter
        switch timeFilter.preset {
        case .today, .yesterday, .thisWeek, .last30Days:
            switchGranularity(.week)
        case .thisMonth, .lastMonth:
            switchGranularity(.month)
        case .thisYear, .lastYear:
            switchGranularity(.year)
        case .allTime, .custom:
            switchGranularity(.month)
        }
    }

    func refreshInsights(timeFilter: TimeFilter) {
        currentTimeFilter = timeFilter
        refreshInsights()
    }
}
