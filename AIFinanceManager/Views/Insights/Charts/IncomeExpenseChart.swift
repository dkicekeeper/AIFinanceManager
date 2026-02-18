//
//  IncomeExpenseChart.swift
//  AIFinanceManager
//
//  Phase 17/18: Financial Insights Feature
//  Grouped bar chart showing income vs expenses.
//  Phase 18 additions:
//  - PeriodDataPoint overload (granularity-aware)
//  - Horizontal scroll when point count exceeds screen width
//

import SwiftUI
import Charts

// MARK: - IncomeExpenseChart (MonthlyDataPoint — legacy)

struct IncomeExpenseChart: View {
    let dataPoints: [MonthlyDataPoint]
    let currency: String
    var compact: Bool = false
    /// When true, wraps in a horizontal ScrollView (Phase 18)
    var scrollable: Bool = false

    private var chartContent: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Month", point.month),
                y: .value("Amount", point.income),
                width: compact ? 6 : 12
            )
            .foregroundStyle(AppColors.success.opacity(0.8))
            .position(by: .value("Type", "Income"))

            BarMark(
                x: .value("Month", point.month),
                y: .value("Amount", point.expenses),
                width: compact ? 6 : 12
            )
            .foregroundStyle(AppColors.destructive.opacity(0.8))
            .position(by: .value("Type", "Expenses"))
        }
        .chartXAxis {
            if compact {
                AxisMarks { _ in }
            } else {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            if compact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatCompact(amount))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Income": AppColors.success,
            "Expenses": AppColors.destructive
        ])
        .chartLegend(compact ? .hidden : .automatic)
        .frame(height: compact ? 60 : 200)
    }

    var body: some View {
        if scrollable && !compact && dataPoints.count > 6 {
            let pointWidth: CGFloat = 50
            let minWidth = UIScreen.main.bounds.width - 48
            let chartWidth = max(minWidth, CGFloat(dataPoints.count) * pointWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                chartContent
                    .frame(width: chartWidth)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            chartContent
        }
    }

    private func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - PeriodIncomeExpenseChart (PeriodDataPoint — Phase 18)

/// Granularity-aware income/expense bar chart.
/// X-axis shows period labels (week/month/quarter/year) instead of raw Date.
/// Always wraps in a horizontal ScrollView when point count exceeds screen width.
struct PeriodIncomeExpenseChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var compact: Bool = false

    private var pointWidth: CGFloat { compact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { compact ? 60 : 220 }

    private var chartWidth: CGFloat {
        let minWidth = UIScreen.main.bounds.width - 48
        return max(minWidth, CGFloat(dataPoints.count) * pointWidth)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chartContent
                .frame(width: compact ? UIScreen.main.bounds.width - 48 : chartWidth,
                       height: chartHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var chartContent: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                width: .fixed(compact ? 6 : max(8, pointWidth * 0.38))
            )
            .foregroundStyle(AppColors.success.opacity(0.8))
            .position(by: .value("Type", "Income"))

            BarMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                width: .fixed(compact ? 6 : max(8, pointWidth * 0.38))
            )
            .foregroundStyle(AppColors.destructive.opacity(0.8))
            .position(by: .value("Type", "Expenses"))
        }
        .chartXAxis {
            if compact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(AppTypography.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if compact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatCompact(amount))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            "Income": AppColors.success,
            "Expenses": AppColors.destructive
        ])
        .chartLegend(compact ? .hidden : .automatic)
    }

    private func formatCompact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Previews

#Preview("Full income/expense chart (legacy)") {
    IncomeExpenseChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT"
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (summary header)") {
    IncomeExpenseChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT",
        compact: true
    )
    .screenPadding()
    .frame(height: 80)
}

#Preview("PeriodIncomeExpenseChart — Monthly") {
    PeriodIncomeExpenseChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
