//
//  InsightsViewModel.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights Feature — Push-model + Granularity
//  ViewModel managing insights state and user interactions.
//
//  Push-model:
//  - Insights are computed in the background when data changes (add/update/delete)
//  - Opening the Insights tab is instant (reads precomputed data, 0ms)
//  - `invalidateAndRecompute()` is called by AppCoordinator.syncTransactionStoreToViewModels()
//  - Background Task computes all granularities; UI reads from `precomputedInsights` cache
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

    // MARK: - Granularity (replaces TimeFilter for Insights)

    private(set) var currentGranularity: InsightGranularity = .month

    /// Legacy: kept for CategoryDeepDive compatibility until it is migrated to granularity.
    private(set) var currentTimeFilter: TimeFilter = TimeFilter(preset: .allTime)

    // MARK: - Computed Properties

    var filteredInsights: [Insight] {
        guard let category = selectedCategory else { return insights }
        return insights.filter { $0.category == category }
    }

    var spendingInsights: [Insight]  { insights.filter { $0.category == .spending } }
    var incomeInsights: [Insight]    { insights.filter { $0.category == .income } }
    var budgetInsights: [Insight]    { insights.filter { $0.category == .budget } }
    var recurringInsights: [Insight] { insights.filter { $0.category == .recurring } }
    var cashFlowInsights: [Insight]  { insights.filter { $0.category == .cashFlow } }
    var wealthInsights: [Insight]    { insights.filter { $0.category == .wealth } }

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

    /// Phase 18: Called when Insights tab appears — triggers computation if stale.
    /// When data is fresh, reads from precomputed cache (0ms).
    func onAppear() {
        if isStale || precomputedInsights[currentGranularity] == nil {
            Self.logger.debug("🧠 [InsightsVM] onAppear — stale or cache MISS, loading")
            isStale = false
            loadInsightsForeground()
        } else {
            Self.logger.debug("🧠 [InsightsVM] onAppear — cache HIT (instant)")
            applyPrecomputed(for: currentGranularity)
        }
    }

    /// Phase 18: Lazy invalidation — marks data as stale instead of eager recompute.
    /// Computation deferred until user opens Insights tab (onAppear).
    /// This eliminates 5-granularity recompute on every transaction change.
    func invalidateAndRecompute() {
        Self.logger.debug("🔄 [InsightsVM] invalidateAndRecompute — marking stale (lazy)")
        insightsService.invalidateCache()
        precomputedInsights = [:]
        precomputedPeriodPoints = [:]
        precomputedTotals = [:]
        isStale = true

        // Phase 18: Cancel any in-flight recompute — will be triggered on next onAppear
        recomputeTask?.cancel()
    }

    /// Legacy compatibility — still called if needed.
    func invalidateCache() {
        invalidateAndRecompute()
    }

    func refreshInsights() {
        Self.logger.debug("🔄 [InsightsVM] refreshInsights — manual refresh")
        PerformanceLogger.shared.reset()
        invalidateAndRecompute()
    }

    func selectCategory(_ category: InsightCategory?) {
        selectedCategory = category
    }

    // MARK: - Category Deep Dive

    func categoryDeepDive(
        categoryName: String
    ) -> (subcategories: [SubcategoryBreakdownItem], monthlyTrend: [MonthlyDataPoint]) {
        insightsService.generateCategoryDeepDive(
            categoryName: categoryName,
            allTransactions: Array(transactionStore.transactions),
            timeFilter: currentTimeFilter,
            baseCurrency: baseCurrency,
            cacheManager: transactionsViewModel.cacheManager,
            currencyService: transactionsViewModel.currencyService
        )
    }

    // MARK: - Private: Background Recompute

    /// Computes insights for ALL granularities in a single background Task.
    /// When done, atomically updates the UI for the currently selected granularity.
    private func recomputeAllGranularities() async {
        guard !Task.isCancelled else { return }

        Self.logger.debug("🔧 [InsightsVM] Background recompute START — \(InsightGranularity.allCases.count) granularities")

        let currency = baseCurrency
        let cacheManager = transactionsViewModel.cacheManager
        let currencyService = transactionsViewModel.currencyService
        let balanceFor: (String) -> Double = { [weak self] accountId in
            self?.transactionsViewModel.calculateTransactionsBalance(for: accountId) ?? 0
        }

        var newInsights = [InsightGranularity: [Insight]]()
        var newPoints   = [InsightGranularity: [PeriodDataPoint]]()
        var newTotals   = [InsightGranularity: PeriodTotals]()

        for granularity in InsightGranularity.allCases {
            guard !Task.isCancelled else { break }

            let computedInsights = insightsService.generateAllInsights(
                granularity: granularity,
                baseCurrency: currency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                balanceFor: balanceFor
            )

            let allTx = Array(transactionStore.transactions)
            let firstDate = allTx.compactMap { DateFormatters.dateFormatter.date(from: $0.date) }.min()
            let points = insightsService.computePeriodDataPoints(
                transactions: allTx,
                granularity: granularity,
                baseCurrency: currency,
                currencyService: currencyService,
                firstTransactionDate: firstDate
            )

            var income: Double = 0; var expenses: Double = 0
            for p in points { income += p.income; expenses += p.expenses }
            let totals = PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)

            newInsights[granularity] = computedInsights
            newPoints[granularity] = points
            newTotals[granularity] = totals
            Self.logger.debug("🔧 [InsightsVM] Granularity .\(granularity.rawValue, privacy: .public) — \(computedInsights.count) insights, \(points.count) points")
        }

        guard !Task.isCancelled else { return }

        // Apply to UI on main actor (already @MainActor, but Task.detached would need explicit hop)
        precomputedInsights = newInsights
        precomputedPeriodPoints = newPoints
        precomputedTotals = newTotals

        // Update visible state for current granularity
        applyPrecomputed(for: currentGranularity)

        Self.logger.debug("🔧 [InsightsVM] Background recompute END")
    }

    /// Applies precomputed data for the given granularity to observable properties.
    private func applyPrecomputed(for granularity: InsightGranularity) {
        insights = precomputedInsights[granularity] ?? []
        periodDataPoints = precomputedPeriodPoints[granularity] ?? []
        let totals = precomputedTotals[granularity]
        totalIncome    = totals?.income   ?? 0
        totalExpenses  = totals?.expenses ?? 0
        netFlow        = totals?.netFlow  ?? 0
        isLoading = false
    }

    /// Foreground fallback (first launch, no precomputed data).
    private func loadInsightsForeground() {
        isLoading = true
        let currency = baseCurrency
        let cacheManager = transactionsViewModel.cacheManager
        let currencyService = transactionsViewModel.currencyService
        let balanceFor: (String) -> Double = { [weak self] accountId in
            self?.transactionsViewModel.calculateTransactionsBalance(for: accountId) ?? 0
        }

        let computedInsights = insightsService.generateAllInsights(
            granularity: currentGranularity,
            baseCurrency: currency,
            cacheManager: cacheManager,
            currencyService: currencyService,
            balanceFor: balanceFor
        )

        let allTx = Array(transactionStore.transactions)
        let firstDate = allTx.compactMap { DateFormatters.dateFormatter.date(from: $0.date) }.min()
        let points = insightsService.computePeriodDataPoints(
            transactions: allTx,
            granularity: currentGranularity,
            baseCurrency: currency,
            currencyService: currencyService,
            firstTransactionDate: firstDate
        )

        var income: Double = 0; var expenses: Double = 0
        for p in points { income += p.income; expenses += p.expenses }

        precomputedInsights[currentGranularity] = computedInsights
        precomputedPeriodPoints[currentGranularity] = points
        precomputedTotals[currentGranularity] = PeriodTotals(income: income, expenses: expenses, netFlow: income - expenses)

        applyPrecomputed(for: currentGranularity)

        // Schedule background computation for the rest of the granularities
        recomputeTask?.cancel()
        recomputeTask = Task { [weak self] in
            await self?.recomputeAllGranularities()
        }
    }

    // MARK: - Legacy loadInsights (for backwards compatibility with any call sites)

    /// Backward-compatible bridge: converts TimeFilter preset to InsightGranularity.
    func loadInsights(timeFilter: TimeFilter) {
        currentTimeFilter = timeFilter
        // Map TimeFilter preset to a granularity
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
