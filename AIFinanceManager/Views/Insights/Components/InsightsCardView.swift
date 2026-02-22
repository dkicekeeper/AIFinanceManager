//
//  InsightsCardView.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Reusable insight card with mini-chart, metric, and trend indicator
//

import SwiftUI

struct InsightsCardView<BottomChart: View>: View {
    let insight: Insight

    @ViewBuilder private let bottomChartContent: () -> BottomChart

    // MARK: - Init (backward compatible — no embedded chart)
    init(insight: Insight) where BottomChart == EmptyView {
        self.insight = insight
        self.bottomChartContent = { EmptyView() }
    }

    // MARK: - Init (with embedded full-size chart)
    init(insight: Insight, @ViewBuilder bottomChart: @escaping () -> BottomChart) {
        self.insight = insight
        self.bottomChartContent = bottomChart
    }

    private var hasBottomChart: Bool {
        BottomChart.self != EmptyView.self
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header: icon + title + conditional mini-chart overlay
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: AppIconSize.md))
                    .foregroundStyle(insight.severity.color)

                Text(insight.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()
            }
            // Mini chart rendered OUTSIDE clip region to avoid being clipped.
            // Hidden when a full-size bottom chart is injected.
            .overlay(alignment: .topTrailing) {
                if !hasBottomChart {
                    miniChart
                        .frame(width: 120, height: 100)
                }
            }

            Text(insight.subtitle)
                .font(AppTypography.bodyLarge)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: AppSpacing.sm) {
                // Large metric
                Text(insight.metric.formattedValue)
                    .font(AppTypography.h2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)

                // Trend indicator
                if let trend = insight.trend {
                    InsightTrendBadge(trend: trend, style: .pill)
                }
                if let unit = insight.metric.unit {
                    Text(unit)
                        .font(AppTypography.bodyLarge)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Full-size chart — shown only when injected via init(insight:bottomChart:)
            if hasBottomChart {
                bottomChartContent()
            }
        }
//        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(radius: AppRadius.pill)
    }

    // MARK: - Mini Chart

    @ViewBuilder
    private var miniChart: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            CategoryBreakdownChart(items: items, mode: .compact)
        case .monthlyTrend(let points):
            CashFlowChart(dataPoints: points, currency: insight.metric.currency ?? "KZT", mode: .compact)
        case .budgetProgressList(let items):
            if let first = items.first {
                budgetProgressBar(first)
            }
        case .recurringList:
            EmptyView()
        case .dailyTrend(let points):
            if !points.isEmpty {
                SpendingTrendChart(
                    dataPoints: points.map { MonthlyDataPoint(id: $0.id, month: $0.date, income: 0, expenses: $0.amount, netFlow: -$0.amount, label: $0.label) },
                    currency: insight.metric.currency ?? "KZT",
                    mode: .compact
                )
            }
        case .accountComparison:
            EmptyView()
        case .periodTrend(let points):
            // Phase 18 — mini period chart.
            // Wealth category uses cumulative balance → WealthChart (accent colour).
            // Other categories use PeriodCashFlowChart (net flow colouring).
            if insight.category == .wealth {
                WealthChart(
                    dataPoints: points,
                    currency: insight.metric.currency ?? "KZT",
                    granularity: points.first?.granularity ?? .month,
                    mode: .compact
                )
                .frame(height: 60)
            } else {
                PeriodCashFlowChart(
                    dataPoints: points,
                    currency: insight.metric.currency ?? "KZT",
                    granularity: points.first?.granularity ?? .month,
                    mode: .compact
                )
                .frame(height: 60)
            }
        case .wealthBreakdown:
            // No mini chart for wealth breakdown (account list)
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    private func budgetProgressBar(_ item: BudgetInsightItem) -> some View {
        BudgetProgressBar(
            percentage: item.percentage,
            isOverBudget: item.isOverBudget,
            color: item.color,
            height: 6
        )
    }
}

// MARK: - Previews

#Preview("Spending — Top Category") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockTopSpending())
            InsightsCardView(insight: .mockMoM())
            InsightsCardView(insight: .mockAvgDaily())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Income & Cash Flow") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockIncomeGrowth())
            InsightsCardView(insight: .mockCashFlow())
            InsightsCardView(insight: .mockProjectedBalance())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Budget & Recurring") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockBudgetOver())
            InsightsCardView(insight: .mockRecurring())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Savings & Forecasting (Phase 24)") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockSavingsRate())
            InsightsCardView(insight: .mockForecasting())
            InsightsCardView(insight: .mockWealthBreakdown())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("With Embedded Chart") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockCashFlow()) {
                CashFlowChart(
                    dataPoints: MonthlyDataPoint.mockTrend(),
                    currency: "KZT",
                    mode: .full
                )
            }
            InsightsCardView(insight: .mockPeriodTrend()) {
                PeriodCashFlowChart(
                    dataPoints: PeriodDataPoint.mockMonthly(),
                    currency: "KZT",
                    granularity: .month,
                    mode: .full
                )
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}
