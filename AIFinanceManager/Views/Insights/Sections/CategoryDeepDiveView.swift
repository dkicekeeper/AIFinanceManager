//
//  CategoryDeepDiveView.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Full category detail: subcategory breakdown, spending trends, anomalies
//

import SwiftUI
import Charts
import os

struct CategoryDeepDiveView: View {
    let categoryName: String
    let color: Color
    let iconSource: IconSource?
    let currency: String
    let viewModel: InsightsViewModel

    @State private var subcategories: [SubcategoryBreakdownItem] = []
    @State private var monthlyTrend: [MonthlyDataPoint] = []
    /// Phase 23-C P16: precomputed index map — eliminates O(n²) firstIndex(where:) in ForEach.
    @State private var subcategoryIndexMap: [String: Int] = [:]

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CategoryDeepDive")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                headerSection

                if !monthlyTrend.isEmpty {
                    trendSection
                }

                if !subcategories.isEmpty {
                    subcategorySection
                }

                if monthlyTrend.count >= 2 {
                    comparisonSection
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
        // Phase 23-A P5: offload heavy computation to background thread
        .task { await loadDataAsync() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: AppSpacing.md) {
            if let iconSource {
                IconView(source: iconSource, size: AppIconSize.xl)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(categoryName)
                    .font(AppTypography.h2)
                    .foregroundStyle(AppColors.textPrimary)

                let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
                FormattedAmountText(
                    amount: totalAmount,
                    currency: currency,
                    fontSize: AppTypography.h3,
                    fontWeight: .semibold,
                    color: color
                )
            }

            Spacer()
        }
        .screenPadding()
    }

    // MARK: - Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.spendingTrend"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .padding([.horizontal, .top], AppSpacing.lg)

            Chart(monthlyTrend) { point in
                BarMark(
                    x: .value("Month", point.month),
                    y: .value("Amount", point.expenses)
                )
                .foregroundStyle(color.opacity(0.7))
                .cornerRadius(AppRadius.xs)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 180)
            .padding([.horizontal, .bottom], AppSpacing.lg)
        }
        .cardBackground(radius: AppRadius.pill)
        .screenPadding()
    }

    // MARK: - Subcategories

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.subcategories"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
                .screenPadding()

            // Donut chart — uses precomputed index map (P16 fix, was O(n²))
            Chart(subcategories, id: \.id) { item in
                SectorMark(
                    angle: .value("Amount", item.amount),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(color.opacity(Double(subcategoryIndexMap[item.id] ?? 0) * 0.15 + 0.3))
            }
            .frame(height: 160)
            .chartLegend(.hidden)
            .screenPadding()

            // List
            ForEach(subcategories) { item in
                HStack {
                    Circle()
                        .fill(color.opacity(Double(subcategoryIndexMap[item.id] ?? 0) * 0.15 + 0.3))
                        .frame(width: 10, height: 10)

                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing) {
                        FormattedAmountText(
                            amount: item.amount,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: AppColors.textPrimary
                        )
                        Text(String(format: "%.1f%%", item.percentage))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
                .screenPadding()
            }
        }
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.periodComparison"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)

            if let current = monthlyTrend.last, monthlyTrend.count >= 2 {
                let previous = monthlyTrend[monthlyTrend.count - 2]
                let change = previous.expenses > 0 ? ((current.expenses - previous.expenses) / previous.expenses) * 100 : 0
                let direction: TrendDirection = change > 2 ? .up : (change < -2 ? .down : .flat)

                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(current.label)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                        FormattedAmountText(
                            amount: current.expenses,
                            currency: currency,
                            fontSize: AppTypography.h3,
                            fontWeight: .bold,
                            color: AppColors.textPrimary
                        )
                    }

                    Spacer()

                    VStack(spacing: AppSpacing.xxs) {
                        Image(systemName: direction == .up ? "arrow.up.right" : (direction == .down ? "arrow.down.right" : "arrow.right"))
                            .foregroundStyle(direction == .up ? AppColors.destructive : (direction == .down ? AppColors.success : AppColors.textSecondary))
                        Text(String(format: "%+.1f%%", change))
                            .font(AppTypography.captionEmphasis)
                            .foregroundStyle(direction == .up ? AppColors.destructive : (direction == .down ? AppColors.success : AppColors.textSecondary))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(previous.label)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                        FormattedAmountText(
                            amount: previous.expenses,
                            currency: currency,
                            fontSize: AppTypography.h3,
                            fontWeight: .semibold,
                            color: AppColors.textSecondary
                        )
                    }
                }
            }
        }
        .glassCardStyle(radius: AppRadius.pill)
        .screenPadding()
    }

    // MARK: - Data Loading

    /// Phase 23-A P5: async — viewModel.categoryDeepDive is CPU-heavy (filter + grouping + 6-month loop).
    /// .task cancels automatically on view disappear.
    /// categoryDeepDive is @MainActor-isolated, so we call it directly (await hops to MainActor),
    /// then offload only the pure index-map build to a detached task if needed.
    @MainActor
    private func loadDataAsync() async {
        Self.logger.debug("🔍 [CategoryDeepDive] OPEN — category='\(categoryName, privacy: .public)'")

        // categoryDeepDive is @MainActor — call directly; Swift hops actors automatically.
        let result = viewModel.categoryDeepDive(categoryName: categoryName)

        // Write results (already on MainActor)
        subcategories = result.subcategories
        monthlyTrend  = result.monthlyTrend
        // Build index map once to avoid O(n²) firstIndex(where:) in body (P16 fix)
        subcategoryIndexMap = Dictionary(
            uniqueKeysWithValues: subcategories.enumerated().map { ($1.id, $0) }
        )

        let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        Self.logger.debug("🔍 [CategoryDeepDive] LOADED — subcategories=\(subcategories.count), months=\(monthlyTrend.count), total=\(String(format: "%.0f", totalAmount), privacy: .public)")
    }
}

// MARK: - Previews

/// Wrapper that injects mock data directly without going through InsightsViewModel
private struct CategoryDeepDivePreview: View {
    @State private var subcategories: [SubcategoryBreakdownItem] = [
        SubcategoryBreakdownItem(id: "restaurants", name: "Restaurants", amount: 42_000, percentage: 49),
        SubcategoryBreakdownItem(id: "groceries",   name: "Groceries",   amount: 28_000, percentage: 33),
        SubcategoryBreakdownItem(id: "delivery",    name: "Delivery",    amount: 15_000, percentage: 18)
    ]
    @State private var monthlyTrend: [MonthlyDataPoint] = MonthlyDataPoint.mockTrend()

    var body: some View {
        // Render sections directly (bypassing loadData) using a read-only version of the view
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Header
                HStack(spacing: AppSpacing.md) {
                    IconView(source: .sfSymbol("fork.knife"), size: AppIconSize.xl)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Food")
                            .font(AppTypography.h2)
                            .foregroundStyle(AppColors.textPrimary)
                        let total = subcategories.reduce(0.0) { $0 + $1.amount }
                        FormattedAmountText(
                            amount: total,
                            currency: "KZT",
                            fontSize: AppTypography.h3,
                            fontWeight: .semibold,
                            color: .orange
                        )
                    }
                    Spacer()
                }
                .screenPadding()

                // Trend chart
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(String(localized: "insights.spendingTrend"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding([.horizontal, .top], AppSpacing.lg)
                    SpendingTrendChart(dataPoints: monthlyTrend, currency: "KZT")
                        .padding([.horizontal, .bottom], AppSpacing.lg)
                }
                .cardBackground(radius: AppRadius.pill)
                .screenPadding()

                // Subcategory list
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(String(localized: "insights.subcategories"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .screenPadding()
                    ForEach(subcategories) { item in
                        HStack {
                            Circle().fill(Color.orange.opacity(0.6)).frame(width: 10, height: 10)
                            Text(item.name).font(AppTypography.body)
                            Spacer()
                            VStack(alignment: .trailing) {
                                FormattedAmountText(
                                    amount: item.amount,
                                    currency: "KZT",
                                    fontSize: AppTypography.body,
                                    fontWeight: .semibold,
                                    color: AppColors.textPrimary
                                )
                                Text(String(format: "%.1f%%", item.percentage))
                                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding(.vertical, AppSpacing.xs)
                        .screenPadding()
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Category Deep Dive — Food") {
    NavigationStack {
        CategoryDeepDivePreview()
    }
}
