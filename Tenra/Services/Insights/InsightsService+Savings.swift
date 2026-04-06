//
//  InsightsService+Savings.swift
//  Tenra
//
//  Savings rate and emergency fund coverage insights.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Savings Insights

    nonisolated func generateSavingsInsights(
        allIncome: Double,
        allExpenses: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double,
        accounts: [Account],
        transactions: [Transaction],
        preAggregated: PreAggregatedData? = nil,
        skipSharedGenerators: Bool = false
    ) -> [Insight] {
        var insights: [Insight] = []

        // SavingsRate is granularity-dependent (uses windowed income/expenses) — always compute
        if let rate = generateSavingsRate(allIncome: allIncome, allExpenses: allExpenses, baseCurrency: baseCurrency) {
            insights.append(rate)
        }
        // EmergencyFund is granularity-independent — skip when shared provided
        if !skipSharedGenerators {
            if let fund = generateEmergencyFund(accounts: accounts, transactions: transactions, baseCurrency: baseCurrency, balanceFor: balanceFor, preAggregated: preAggregated) {
                insights.append(fund)
            }
        }
        return insights
    }

    // MARK: - Private Savings Sub-Generators

    private nonisolated func generateSavingsRate(allIncome: Double, allExpenses: Double, baseCurrency: String) -> Insight? {
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

    private nonisolated func generateEmergencyFund(accounts: [Account], transactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let totalBalance = accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard totalBalance > 0 else { return nil }

        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let aggregates: [InMemoryMonthlyTotal]
        if let preAggregated {
            aggregates = preAggregated.lastMonthlyTotals(3)
        } else {
            aggregates = Self.computeLastMonthlyTotals(3, from: transactions, baseCurrency: baseCurrency)
        }
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

}
