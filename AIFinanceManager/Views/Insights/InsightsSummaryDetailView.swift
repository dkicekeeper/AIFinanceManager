//
//  InsightsSummaryDetailView.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights Feature
//  Full-screen detail view shown when the InsightsSummaryHeader is tapped.
//  Displays income, expenses, net flow for all time and the
//  period-by-period income/expense trend chart with a breakdown list.
//

import SwiftUI

struct InsightsSummaryDetailView: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currency: String
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity

    init(
        totalIncome: Double,
        totalExpenses: Double,
        netFlow: Double,
        currency: String,
        periodDataPoints: [PeriodDataPoint],
        granularity: InsightGranularity
    ) {
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.netFlow = netFlow
        self.currency = currency
        self.periodDataPoints = periodDataPoints
        self.granularity = granularity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Period totals
                periodTotalsSection

                // Full-size income/expense chart
                if periodDataPoints.count >= 2 {
                    chartSection
                }

                // Period breakdown list
                if !periodDataPoints.isEmpty {
                    periodListSection
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(granularity.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period Totals

    private var periodTotalsSection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                totalItem(
                    title: String(localized: "insights.income"),
                    amount: totalIncome,
                    color: AppColors.success
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.expenses"),
                    amount: totalExpenses,
                    color: AppColors.destructive
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.netFlow"),
                    amount: netFlow,
                    color: netFlow >= 0 ? AppColors.success : AppColors.destructive
                )
            }
        }
        .glassCardStyle(radius: AppRadius.pill)
        .screenPadding()
    }

    private func totalItem(title: String, amount: Double, color: Color) -> some View {
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

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.cashFlowTrend"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .padding([.horizontal, .top], AppSpacing.lg)

            PeriodIncomeExpenseChart(
                dataPoints: periodDataPoints,
                currency: currency,
                granularity: granularity,
                mode: .full
            )
            .padding([.horizontal, .bottom], AppSpacing.lg)
        }
        .cardBackground(radius: AppRadius.pill)
        .screenPadding()
    }

    // MARK: - Period List

    private var periodListSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.monthlyBreakdown"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .screenPadding()

            ForEach(periodDataPoints.reversed()) { point in
                HStack {
                    Text(point.label)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(minWidth: 80, alignment: .leading)

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        FormattedAmountText(
                            amount: point.netFlow,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: point.netFlow >= 0 ? AppColors.success : AppColors.destructive
                        )
                        HStack(spacing: AppSpacing.xs) {
                            FormattedAmountText(
                                amount: point.income,
                                currency: currency,
                                prefix: "+",
                                fontSize: AppTypography.caption,
                                fontWeight: .regular,
                                color: AppColors.success
                            )
                            FormattedAmountText(
                                amount: point.expenses,
                                currency: currency,
                                prefix: "-",
                                fontSize: AppTypography.caption,
                                fontWeight: .regular,
                                color: AppColors.destructive
                            )
                        }
                    }
                }
                .padding(.vertical, AppSpacing.sm)
                .screenPadding()

                Divider()
                    .padding(.leading, AppSpacing.lg)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 5_450_387,
            totalExpenses: 1_904_618,
            netFlow: 3_545_769,
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockMonthly(),
            granularity: .month
        )
    }
}
