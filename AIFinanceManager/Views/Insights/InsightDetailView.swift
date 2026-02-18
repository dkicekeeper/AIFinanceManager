//
//  InsightDetailView.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Detail drill-down view for a tapped insight card
//

import SwiftUI
import os

struct InsightDetailView: View {
    let insight: Insight
    let currency: String
    /// Optional — needed only for category drill-down navigation (category items → CategoryDeepDiveView)
    var viewModel: InsightsViewModel? = nil

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
            Self.logger.debug("📋 [InsightDetail] OPEN — type=\(String(describing: insight.type), privacy: .public), category=\(String(describing: insight.category), privacy: .public), metric=\(insight.metric.formattedValue, privacy: .public), drillDown=\(viewModel != nil)")
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
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: trend.trendIcon)
                        if let percent = trend.changePercent {
                            Text(String(format: "%+.1f%%", percent))
                        }
                    }
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(trend.trendColor)
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
                CategoryBreakdownChart(items: items)
            case .monthlyTrend(let points):
                CashFlowChart(dataPoints: points, currency: currency)
            case .periodTrend(let points):
                // Phase 18 — granularity-aware chart
                PeriodCashFlowChart(
                    dataPoints: points,
                    currency: currency,
                    granularity: points.first?.granularity ?? .month
                )
            case .budgetProgressList(let items):
                budgetChartSection(items)
            case .recurringList:
                EmptyView()
            case .dailyTrend(let points):
                SpendingTrendChart(
                    dataPoints: points.map { MonthlyDataPoint(id: $0.id, month: $0.date, income: 0, expenses: $0.amount, netFlow: -$0.amount, label: $0.label) },
                    currency: currency
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

    private func budgetChartSection(_ items: [BudgetInsightItem]) -> some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        if let iconSource = item.iconSource {
                            IconView(source: iconSource, size: AppIconSize.lg)
                        }
                        Text(item.categoryName)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f%%", item.percentage))
                            .font(AppTypography.bodySmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(item.isOverBudget ? AppColors.destructive : AppColors.textPrimary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: AppRadius.xs)
                                .fill(AppColors.secondaryBackground)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: AppRadius.xs)
                                .fill(item.isOverBudget ? AppColors.destructive : item.color)
                                .frame(
                                    width: min(geometry.size.width, geometry.size.width * min(item.percentage, 100) / 100),
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text(Formatting.formatCurrencySmart(item.spent, currency: currency))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text("/")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(Formatting.formatCurrencySmart(item.budgetAmount, currency: currency))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        if item.daysRemaining > 0 {
                            Text(String(format: String(localized: "insights.daysLeft"), item.daysRemaining))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
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
            EmptyView() // Already shown in chart section
        case .monthlyTrend(let points):
            monthlyDetailList(points)
        case .periodTrend(let points):
            periodDetailList(points)
        case .wealthBreakdown(let accounts):
            accountDetailList(accounts)
        default:
            EmptyView()
        }
    }

    private func categoryDetailList(_ items: [CategoryBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.breakdown"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
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
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text(Formatting.formatCurrencySmart(item.amount, currency: currency))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                    Text(String(format: "%.1f%%", item.percentage))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                // Chevron appears only when drill-down is available
                if viewModel != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .screenPadding()

        if let vm = viewModel {
            let catStore = vm  // capture for NavigationLink
            NavigationLink(destination: CategoryDeepDiveView(
                categoryName: item.categoryName,
                color: item.color,
                iconSource: item.iconSource,
                currency: currency,
                viewModel: catStore
            )) {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private func recurringDetailList(_ items: [RecurringInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.breakdown"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
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
                        Text(Formatting.formatCurrencySmart(item.monthlyEquivalent, currency: currency))
                            .font(AppTypography.body)
                            .fontWeight(.semibold)
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

    // MARK: - Phase 18 detail lists

    private func periodDetailList(_ points: [PeriodDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.monthlyBreakdown"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .screenPadding()

            ForEach(points.reversed()) { point in
                HStack {
                    Text(point.label)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

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
                            Text("+\(Formatting.formatCurrencySmart(point.income, currency: currency))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.success)
                            Text("-\(Formatting.formatCurrencySmart(point.expenses, currency: currency))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.destructive)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.sm)
                .screenPadding()
            }
        }
    }

    private func accountDetailList(_ accounts: [AccountInsightItem]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.wealth.accounts"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
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

    private func monthlyDetailList(_ points: [MonthlyDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "insights.monthlyBreakdown"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .screenPadding()

            ForEach(points.reversed()) { point in
                HStack {
                    Text(point.label)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

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
                            Text("+\(Formatting.formatCurrencySmart(point.income, currency: currency))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.success)
                            Text("-\(Formatting.formatCurrencySmart(point.expenses, currency: currency))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.destructive)
                        }
                    }
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
