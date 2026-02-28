//
//  InsightsService+Wealth.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: total wealth, wealth growth, account dormancy detection.
//

import CoreData
import Foundation
import os

extension InsightsService {

    // MARK: - Wealth Insights (Phase 18)

    @MainActor
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

        let totalWealth = accounts.reduce(0.0) { $0 + balanceFor($1.id) }

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

        // Period-over-period comparison
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

        // Wealth Growth (Phase 24)
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

    // MARK: - Account Dormancy (Phase 24 Behavioral)

    /// Flags accounts that have been idle for 30+ days but still hold a positive balance.
    @MainActor
    func generateAccountDormancy(allTransactions: [Transaction], balanceFor: (String) -> Double) -> Insight? {
        let now = Date()
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return nil }

        // Phase 31: Fetch last transaction dates from CoreData (full history, not windowed store).
        let lastDates = fetchLastTransactionDates()

        let dormantAccounts: [AccountInsightItem] = transactionStore.accounts.compactMap { account in
            let balance = balanceFor(account.id)
            guard balance > 0 else { return nil }
            let lastTx: Date?
            if let cdDate = lastDates[account.id] {
                lastTx = cdDate
            } else {
                let dateFormatter = DateFormatters.dateFormatter
                lastTx = allTransactions
                    .filter { $0.accountId == account.id }
                    .compactMap { dateFormatter.date(from: $0.date) }
                    .max()
            }
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

    // MARK: - CoreData Helper

    /// Phase 31: Fetch the most recent transaction date per accountId directly from CoreData.
    /// Bypasses the windowed transactionStore.transactions — detects dormancy beyond windowMonths.
    @MainActor
    private func fetchLastTransactionDates() -> [String: Date] {
        let context = CoreDataStack.shared.viewContext
        let request = NSFetchRequest<NSDictionary>(entityName: "TransactionEntity")
        request.propertiesToFetch = ["accountId", "date"]
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "accountId != nil AND date != nil")

        var result: [String: Date] = [:]
        do {
            let rows = try context.fetch(request) as! [[String: Any]]
            for row in rows {
                guard let accountId = row["accountId"] as? String,
                      let date = row["date"] as? Date else { continue }
                if let existing = result[accountId] {
                    if date > existing { result[accountId] = date }
                } else {
                    result[accountId] = date
                }
            }
        } catch {
            Self.logger.error("❌ [Insights] fetchLastTransactionDates failed: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }
}
