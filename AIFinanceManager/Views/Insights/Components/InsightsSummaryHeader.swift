//
//  InsightsSummaryHeader.swift
//  AIFinanceManager
//
//  Phase 23: P7 — switched from MonthlyDataPoint to PeriodDataPoint.
//  Eliminates per-render .map { $0.asMonthlyDataPoint() } allocation in InsightsView.body.
//

import SwiftUI
import os

struct InsightsSummaryHeader: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currency: String
    /// Phase 23 P7: PeriodDataPoint instead of MonthlyDataPoint — no conversion needed.
    let periodDataPoints: [PeriodDataPoint]

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsSummaryHeader")

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.lg) {
                summaryItem(
                    title: String(localized: "insights.income"),
                    amount: totalIncome,
                    color: AppColors.success
                )

                Spacer()

                summaryItem(
                    title: String(localized: "insights.expenses"),
                    amount: totalExpenses,
                    color: AppColors.destructive
                )

                Spacer()

                summaryItem(
                    title: String(localized: "insights.netFlow"),
                    amount: netFlow,
                    color: netFlow >= 0 ? AppColors.success : AppColors.destructive
                )
            }

            // Mini trend chart.
            // Using cardBackground (not glassCardStyle) so clipShape doesn't cut Charts layers.
            if periodDataPoints.count >= 2 {
                PeriodIncomeExpenseChart(
                    dataPoints: periodDataPoints,
                    currency: currency,
                    granularity: periodDataPoints.first?.granularity ?? .month,
                    compact: true
                )
            }
        }
        .glassCardStyle(radius: AppRadius.pill)
        .onAppear {
            Self.logger.debug("📊 [SummaryHeader] RENDER — income=\(String(format: "%.0f", totalIncome), privacy: .public), expenses=\(String(format: "%.0f", totalExpenses), privacy: .public), net=\(String(format: "%.0f", netFlow), privacy: .public) \(currency, privacy: .public), pts=\(periodDataPoints.count)")
        }
    }

    private func summaryItem(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: AppTypography.bodySmall,
                fontWeight: .semibold,
                color: color
            )
        }
    }
}

// MARK: - Previews

#Preview("With trend chart") {
    InsightsSummaryHeader(
        totalIncome: 530_000,
        totalExpenses: 320_000,
        netFlow: 210_000,
        currency: "KZT",
        periodDataPoints: PeriodDataPoint.mockMonthly()
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Negative net flow") {
    InsightsSummaryHeader(
        totalIncome: 280_000,
        totalExpenses: 340_000,
        netFlow: -60_000,
        currency: "KZT",
        periodDataPoints: PeriodDataPoint.mockMonthly()
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("No trend data") {
    InsightsSummaryHeader(
        totalIncome: 450_000,
        totalExpenses: 310_000,
        netFlow: 140_000,
        currency: "USD",
        periodDataPoints: []
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
