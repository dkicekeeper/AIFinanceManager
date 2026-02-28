//
//  InsightsService+HealthScore.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: composite financial health score (0-100, 5 weighted components).
//

import Foundation
import SwiftUI

extension InsightsService {

    // MARK: - Financial Health Score (Phase 24)

    /// Computes a composite 0-100 financial health score from five weighted components.
    /// Call after `generateAllInsights` once totals and period data points are available.
    @MainActor
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
        case 80...100: (grade, gradeColor) = (String(localized: "insights.healthGrade.excellent"),      AppColors.success)
        case 60..<80:  (grade, gradeColor) = (String(localized: "insights.healthGrade.good"),           AppColors.accent)
        case 40..<60:  (grade, gradeColor) = (String(localized: "insights.healthGrade.fair"),           AppColors.warning)
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
}
