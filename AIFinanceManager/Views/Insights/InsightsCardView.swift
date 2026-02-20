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

    private let hasBottomChart: Bool
    @ViewBuilder private let bottomChartContent: () -> BottomChart

    // MARK: - Init (backward compatible — no embedded chart)
    init(insight: Insight) where BottomChart == EmptyView {
        self.insight = insight
        self.hasBottomChart = false
        self.bottomChartContent = { EmptyView() }
    }

    // MARK: - Init (with embedded full-size chart)
    init(insight: Insight, @ViewBuilder bottomChart: @escaping () -> BottomChart) {
        self.insight = insight
        self.hasBottomChart = true
        self.bottomChartContent = bottomChart
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
                    // Mini chart rendered OUTSIDE clip region to avoid being clipped.
                    // Hidden when a full-size bottom chart is injected.
                    .overlay(alignment: .topTrailing) {
                        if !hasBottomChart {
                            miniChart
                                .frame(width: 120, height: 100)
                        }
                    }
            }

            Text(insight.subtitle)
                .font(AppTypography.h4)
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
                    trendBadge(trend)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(radius: AppRadius.pill)
    }

    // MARK: - Trend Badge

    private func trendBadge(_ trend: InsightTrend) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: trend.trendIcon)
                .font(AppTypography.caption2.weight(.bold))

            if let percent = trend.changePercent {
                Text(String(format: "%+.1f%%", percent))
                    .font(AppTypography.caption2)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(trend.trendColor)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(trend.trendColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Mini Chart

    @ViewBuilder
    private var miniChart: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            CategoryBreakdownChart(items: items, compact: true)
        case .monthlyTrend(let points):
            CashFlowChart(dataPoints: points, currency: insight.metric.currency ?? "KZT", compact: true)
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
                    compact: true
                )
            }
        case .accountComparison:
            EmptyView()
        case .periodTrend(let points):
            // Phase 18 — mini period cash flow chart
            PeriodCashFlowChart(
                dataPoints: points,
                currency: insight.metric.currency ?? "KZT",
                granularity: points.first?.granularity ?? .month,
                compact: true
            )
            .frame(height: 60)
        case .wealthBreakdown:
            // No mini chart for wealth breakdown (account list)
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    // P9 (card): scaleEffect replaces GeometryReader — no layout thrash
    private func budgetProgressBar(_ item: BudgetInsightItem) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(AppColors.secondaryBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 6)

            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(item.isOverBudget ? AppColors.destructive : item.color)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .scaleEffect(x: min(item.percentage, 100) / 100, anchor: .leading)
        }
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
