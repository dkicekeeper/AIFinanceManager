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

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CategoryDeepDive")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Category header
                headerSection

                // Monthly spending trend
                if !monthlyTrend.isEmpty {
                    trendSection
                }

                // Subcategory breakdown
                if !subcategories.isEmpty {
                    subcategorySection
                }

                // Period comparison
                if monthlyTrend.count >= 2 {
                    comparisonSection
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadData() }
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
                Text(Formatting.formatCurrencySmart(totalAmount, currency: currency))
                    .font(AppTypography.h3)
                    .foregroundStyle(color)
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

            // Donut chart
            Chart(subcategories, id: \.id) { item in
                SectorMark(
                    angle: .value("Amount", item.amount),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(color.opacity(Double(subcategories.firstIndex(where: { $0.id == item.id }) ?? 0) * 0.15 + 0.3))
            }
            .frame(height: 160)
            .chartLegend(.hidden)
            .screenPadding()

            // List
            ForEach(subcategories) { item in
                HStack {
                    Circle()
                        .fill(color.opacity(Double(subcategories.firstIndex(where: { $0.id == item.id }) ?? 0) * 0.15 + 0.3))
                        .frame(width: 10, height: 10)

                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text(Formatting.formatCurrencySmart(item.amount, currency: currency))
                            .font(AppTypography.body)
                            .fontWeight(.semibold)
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
                        Text(Formatting.formatCurrencySmart(current.expenses, currency: currency))
                            .font(AppTypography.h3)
                            .fontWeight(.bold)
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
                        Text(Formatting.formatCurrencySmart(previous.expenses, currency: currency))
                            .font(AppTypography.h3)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .glassCardStyle(radius: AppRadius.pill)
        .screenPadding()
    }

    // MARK: - Data Loading

    private func loadData() {
        Self.logger.debug("🔍 [CategoryDeepDive] OPEN — category='\(categoryName, privacy: .public)', currency=\(currency, privacy: .public)")
        let result = viewModel.categoryDeepDive(categoryName: categoryName)
        subcategories = result.subcategories
        monthlyTrend = result.monthlyTrend
        let totalAmount = subcategories.reduce(0.0) { $0 + $1.amount }
        Self.logger.debug("🔍 [CategoryDeepDive] LOADED — subcategories=\(subcategories.count), months=\(monthlyTrend.count), total=\(String(format: "%.0f", totalAmount), privacy: .public) \(currency, privacy: .public)")
        for sub in subcategories.prefix(5) {
            Self.logger.debug("   📂 \(sub.name, privacy: .public): \(String(format: "%.0f", sub.amount), privacy: .public) (\(String(format: "%.1f%%", sub.percentage), privacy: .public))")
        }
        for point in monthlyTrend {
            Self.logger.debug("   📅 \(point.label, privacy: .public): exp=\(String(format: "%.0f", point.expenses), privacy: .public)")
        }
    }
}

// MARK: - Previews

/// Wrapper that injects mock data directly without going through InsightsViewModel
private struct CategoryDeepDivePreview: View {
    @State private var subcategories: [SubcategoryBreakdownItem] = [
        SubcategoryBreakdownItem(id: "restaurants", name: "Рестораны",     amount: 42_000, percentage: 49),
        SubcategoryBreakdownItem(id: "groceries",   name: "Продукты",      amount: 28_000, percentage: 33),
        SubcategoryBreakdownItem(id: "delivery",    name: "Доставка еды",  amount: 15_000, percentage: 18)
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
                        Text("Еда")
                            .font(AppTypography.h2)
                            .foregroundStyle(AppColors.textPrimary)
                        let total = subcategories.reduce(0.0) { $0 + $1.amount }
                        Text(Formatting.formatCurrencySmart(total, currency: "KZT"))
                            .font(AppTypography.h3)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                .screenPadding()

                // Trend chart
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Тренд расходов")
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
                    Text("Подкатегории")
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .screenPadding()
                    ForEach(subcategories) { item in
                        HStack {
                            Circle().fill(Color.orange.opacity(0.6)).frame(width: 10, height: 10)
                            Text(item.name).font(AppTypography.body)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Formatting.formatCurrencySmart(item.amount, currency: "KZT"))
                                    .font(AppTypography.body).fontWeight(.semibold)
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
        .navigationTitle("Еда")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Category Deep Dive — Еда") {
    NavigationStack {
        CategoryDeepDivePreview()
    }
}
