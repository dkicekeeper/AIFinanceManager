//
//  InsightDetailView.swift
//  AIFinanceManager
//
//  Phase 23: UI fixes
//  - P9: viewModel replaced with onCategoryTap closure — SRP, no full ViewModel dependency
//  - P10: monthlyDetailList + periodDetailList merged into single periodBreakdownList
//  - P22: budgetChartSection uses LazyVStack
//

import SwiftUI
import os

struct InsightDetailView: View {
    let insight: Insight
    let currency: String
    /// P9: SRP — pass only what's needed for drill-down, not the entire ViewModel.
    /// Nil = no drill-down chevron shown.
    var onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightDetailView")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Header
                headerSection

                // Full-size chart
                chartSection

                // Detail breakdown
                detailSection
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(insight.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Self.logger.debug("📋 [InsightDetail] OPEN — type=\(String(describing: insight.type), privacy: .public), category=\(String(describing: insight.category), privacy: .public), metric=\(insight.metric.formattedValue, privacy: .public), drillDown=\(onCategoryTap != nil)")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: insight.severity.icon)
                    .foregroundStyle(insight.severity.color)
                Text(insight.subtitle)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if let trend = insight.trend {
                    InsightTrendBadge(trend: trend, style: .inline)
                }
            }

            Text(insight.metric.formattedValue)
                .font(AppTypography.h1)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.textPrimary)

            if let trend = insight.trend {
                Text(trend.comparisonPeriod)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .screenPadding()
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        Group {
            switch insight.detailData {
            case .categoryBreakdown(let items):
                CategoryBreakdownChart(items: items, mode: .full)
            case .monthlyTrend(let points):
                CashFlowChart(dataPoints: points, currency: currency, mode: .full)
            case .periodTrend(let points):
                // Phase 18 — granularity-aware chart
                PeriodCashFlowChart(
                    dataPoints: points,
                    currency: currency,
                    granularity: points.first?.granularity ?? .month,
                    mode: .full
                )
            case .budgetProgressList(let items):
                budgetChartSection(items)
            case .recurringList:
                EmptyView()
            case .dailyTrend(let points):
                SpendingTrendChart(
                    dataPoints: points.map { MonthlyDataPoint(id: $0.id, month: $0.date, income: 0, expenses: $0.amount, netFlow: -$0.amount, label: $0.label) },
                    currency: currency,
                    mode: .full
                )
            case .accountComparison:
                EmptyView()
            case .wealthBreakdown:
                // Account balance list rendered in detailSection
                EmptyView()
            case nil:
                EmptyView()
            }
        }
        .screenPadding()
    }

    // P22: LazyVStack eliminates upfront layout of all budget rows
    private func budgetChartSection(_ items: [BudgetInsightItem]) -> some View {
        LazyVStack(spacing: AppSpacing.md) {
            ForEach(items) { item in
                BudgetProgressRow(item: item, currency: currency)
            }
        }
    }

    // MARK: - Detail Section

    @ViewBuilder
    private var detailSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            categoryDetailList(items)
        case .recurringList(let items):
            recurringDetailList(items)
        case .budgetProgressList:
            EmptyView()
        // P10: monthlyTrend and periodTrend share one rendering function
        case .monthlyTrend(let points):
            periodBreakdownList(points.map { BreakdownPoint(label: $0.label, income: $0.income, expenses: $0.expenses, netFlow: $0.netFlow) })
        case .periodTrend(let points):
            periodBreakdownList(points.map { BreakdownPoint(label: $0.label, income: $0.income, expenses: $0.expenses, netFlow: $0.netFlow) })
        case .wealthBreakdown(let accounts):
            accountDetailList(accounts)
        default:
            EmptyView()
        }
    }

    /// Unified point model for breakdown list — eliminates monthlyDetailList/periodDetailList duplication.
    private struct BreakdownPoint {
        let label: String
        let income: Double
        let expenses: Double
        let netFlow: Double
    }

    private func categoryDetailList(_ items: [CategoryBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.breakdown"), style: .insights)
                .screenPadding()

            ForEach(items) { item in
                categoryRow(item)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ item: CategoryBreakdownItem) -> some View {
        let rowContent = HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(item.color)
                .frame(width: 12, height: 12)

            if let iconSource = item.iconSource {
                IconView(source: iconSource, size: AppIconSize.lg)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                if !item.subcategories.isEmpty {
                    Text(item.subcategories.prefix(3).map(\.name).joined(separator: ", "))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                AmountWithPercentage(
                    amount: item.amount,
                    currency: currency,
                    percentage: item.percentage
                )
                // P9: chevron only when drill-down closure is provided
                if onCategoryTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .screenPadding()

        // P9: drill-down destination provided by caller via closure (AnyView)
        if let destination = onCategoryTap?(item) {
            NavigationLink(destination: destination) {
                rowContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private func recurringDetailList(_ items: [RecurringInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.breakdown"), style: .insights)
                .screenPadding()

            ForEach(items) { item in
                HStack(spacing: AppSpacing.md) {
                    if let iconSource = item.iconSource {
                        IconView(source: iconSource, size: AppIconSize.lg)
                    } else {
                        Image(systemName: "repeat.circle")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(item.name)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(item.frequency.displayName)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        FormattedAmountText(
                            amount: item.monthlyEquivalent,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: AppColors.textPrimary
                        )
                        Text(String(localized: "insights.perMonth"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.sm)
                .screenPadding()
            }
        }
    }

    // P10: Single unified function replacing monthlyDetailList + periodDetailList.
    private func periodBreakdownList(_ points: [BreakdownPoint]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.monthlyBreakdown"), style: .insights)
                .screenPadding()

            ForEach(points.reversed(), id: \.label) { point in
                PeriodBreakdownRow(
                    label: point.label,
                    income: point.income,
                    expenses: point.expenses,
                    netFlow: point.netFlow,
                    currency: currency
                )
            }
        }
    }

    private func accountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.wealth.accounts"), style: .insights)
                .screenPadding()

            ForEach(accounts) { account in
                HStack(spacing: AppSpacing.md) {
                    if let iconSource = account.iconSource {
                        IconView(source: iconSource, size: AppIconSize.lg)
                    } else {
                        Image(systemName: "building.columns")
                            .font(.system(size: AppIconSize.md))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(account.accountName)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(account.currency)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    FormattedAmountText(
                        amount: account.balance,
                        currency: currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: account.balance >= 0 ? AppColors.textPrimary : AppColors.destructive
                    )
                }
                .padding(.vertical, AppSpacing.sm)
                .screenPadding()
            }
        }
    }

}

// MARK: - Previews

#Preview("Category Breakdown") {
    NavigationStack {
        InsightDetailView(insight: .mockTopSpending(), currency: "KZT")
    }
}

#Preview("Cash Flow Trend") {
    NavigationStack {
        InsightDetailView(insight: .mockCashFlow(), currency: "KZT")
    }
}

#Preview("Budget Overspend") {
    NavigationStack {
        InsightDetailView(insight: .mockBudgetOver(), currency: "KZT")
    }
}

#Preview("Recurring Payments") {
    NavigationStack {
        InsightDetailView(insight: .mockRecurring(), currency: "KZT")
    }
}

#Preview("Income Growth") {
    NavigationStack {
        InsightDetailView(insight: .mockIncomeGrowth(), currency: "KZT")
    }
}
