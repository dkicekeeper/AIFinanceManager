//
//  InsightsSummaryHeader.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Summary header showing income/expenses/net flow with mini trend chart
//

import SwiftUI
import os

struct InsightsSummaryHeader: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currency: String
    let monthlyTrend: [MonthlyDataPoint]

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsSummaryHeader")

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Summary amounts — padded inside the card
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
            .padding([.horizontal, .top], AppSpacing.lg)

            // Mini trend chart — rendered AFTER the text section with its own padding.
            // Using cardBackground (not glassCardStyle) so clipShape doesn't cut Charts layers.
            if monthlyTrend.count >= 2 {
                IncomeExpenseChart(
                    dataPoints: monthlyTrend,
                    currency: currency,
                    compact: true
                )
                .padding([.horizontal, .bottom], AppSpacing.lg)
            }
        }
        .cardBackground(radius: AppRadius.pill)
        .onAppear {
            let inc = String(format: "%.0f", totalIncome)
            let exp = String(format: "%.0f", totalExpenses)
            let net = String(format: "%.0f", netFlow)
            Self.logger.debug("📊 [SummaryHeader] RENDER — income=\(inc, privacy: .public), expenses=\(exp, privacy: .public), net=\(net, privacy: .public) \(currency, privacy: .public), trendPoints=\(monthlyTrend.count)")
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
        monthlyTrend: MonthlyDataPoint.mockTrend()
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
        monthlyTrend: MonthlyDataPoint.mockTrend()
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
        monthlyTrend: []
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
