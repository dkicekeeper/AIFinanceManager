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
//  Phase 23-C: Replaced UIScreen.main.bounds with GeometryReader — no UIKit dependency.
//

import SwiftUI
import Charts

// MARK: - IncomeExpenseChart (MonthlyDataPoint — legacy)

struct IncomeExpenseChart: View {
    let dataPoints: [MonthlyDataPoint]
    let currency: String
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }
    /// When true, wraps in a horizontal ScrollView (Phase 18)
    var scrollable: Bool = false

    private var chartContent: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Month", point.month),
                y: .value("Amount", point.income),
                width: isCompact ? 6 : 12
            )
            .cornerRadius(AppRadius.circle) // pill/capsule bars — intentional .infinity
            .foregroundStyle(AppColors.success.opacity(0.85))
            .shadow(color: AppColors.success.opacity(0.5), radius: 8, x: 0, y: 0)
            .position(by: .value("Type", "Income"))

            BarMark(
                x: .value("Month", point.month),
                y: .value("Amount", point.expenses),
                width: isCompact ? 6 : 12
            )
            .cornerRadius(AppRadius.circle) // pill/capsule bars — intentional .infinity
            .foregroundStyle(AppColors.destructive.opacity(0.85))
            .shadow(color: AppColors.destructive.opacity(0.5), radius: 8, x: 0, y: 0)
            .position(by: .value("Type", "Expenses"))
        }
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisDate(date))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if isCompact {
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
        .chartLegend(isCompact ? .hidden : .automatic)
        .chartPlotStyle { content in
            if isCompact {
                content
            } else {
                content.padding(.trailing, AppSpacing.md)
            }
        }
        .frame(height: isCompact ? 60 : 200)
    }

    var body: some View {
        if scrollable && !isCompact && dataPoints.count > 6 {
            let pointWidth: CGFloat = 50
            GeometryReader { proxy in
                let chartWidth = max(proxy.size.width, CGFloat(dataPoints.count) * pointWidth)
                ScrollView(.horizontal, showsIndicators: false) {
                    chartContent
                        .frame(width: chartWidth)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(height: 200)
        } else {
            chartContent
        }
    }

    /// Cached formatter for X-axis month labels. Locale captured at first use.
    /// Re-assigning `locale` is a reference assignment (cheap); no re-allocation.
    private static let axisMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    /// Форматирует дату для X-оси: 3 chars uppercase + год если не текущий.
    /// Пример: "ЯНВ" (текущий год), "ЯНВ'24" (другой год). Локаль-зависимо.
    private func formatAxisDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let dateYear = calendar.component(.year, from: date)

        Self.axisMonthFormatter.locale = .current
        let month = String(Self.axisMonthFormatter.string(from: date).uppercased().prefix(3))

        if dateYear == currentYear {
            return month
        } else {
            return "\(month)'\(String(format: "%02d", dateYear % 100))"
        }
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
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 220 }

    private func chartWidth(containerWidth: CGFloat) -> CGFloat {
        max(containerWidth, CGFloat(dataPoints.count) * pointWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                chartContent
                    .frame(width: isCompact ? container : chartWidth(containerWidth: container),
                           height: chartHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: chartHeight)
    }

    private var chartContent: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                width: .fixed(isCompact ? 6 : max(8, pointWidth * 0.38))
            )
            .cornerRadius(AppRadius.circle) // pill/capsule bars — intentional .infinity
            .foregroundStyle(AppColors.success.opacity(0.85))
            .shadow(color: AppColors.success.opacity(0.35), radius: 4, x: 0, y: 2)
            .position(by: .value("Type", "Income"))

            BarMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                width: .fixed(isCompact ? 6 : max(8, pointWidth * 0.38))
            )
            .cornerRadius(AppRadius.circle) // pill/capsule bars — intentional .infinity
            .foregroundStyle(AppColors.destructive.opacity(0.85))
            .shadow(color: AppColors.destructive.opacity(0.35), radius: 4, x: 0, y: 2)
            .position(by: .value("Type", "Expenses"))
        }

        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(axisLabelMap[label] ?? label)
                                .font(AppTypography.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }

        .chartYAxis {
            if isCompact {
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
        .chartLegend(isCompact ? .hidden : .automatic)
        .chartPlotStyle { content in
            if isCompact {
                content
            } else {
                content.padding(.trailing, AppSpacing.md)
            }
        }
    }

    private func formatCompact(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if abs(value) >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    /// Маппинг полный label → компактный label для X-оси.
    /// Строится из dataPoints при каждом создании View (несущественные затраты для ≤52 точек).
    private var axisLabelMap: [String: String] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM"
        return Dictionary(
            uniqueKeysWithValues: dataPoints.map { point in
                (point.label, compactPeriodLabel(
                    point: point,
                    calendar: calendar,
                    currentYear: currentYear,
                    formatter: formatter
                ))
            }
        )
    }

    /// Возвращает компактный лейбл для X-оси по гранулярности.
    /// .month   → "ЯНВ" / "ЯНВ'25"
    /// .week    → "W07" / "W07'25"
    /// .quarter → "Q1" / "Q1'25"
    /// .year    → "2025" (полный год)
    /// .allTime → оригинальный лейбл
    private func compactPeriodLabel(
        point: PeriodDataPoint,
        calendar: Calendar,
        currentYear: Int,
        formatter: DateFormatter
    ) -> String {
        let pointYear = calendar.component(.year, from: point.periodStart)
        let shortYear = String(format: "%02d", pointYear % 100)

        switch point.granularity {
        case .month:
            let month = String(formatter.string(from: point.periodStart).uppercased().prefix(3))
            return pointYear == currentYear ? month : "\(month)'\(shortYear)"

        case .week:
            let weekNum = calendar.component(.weekOfYear, from: point.periodStart)
            return pointYear == currentYear
                ? String(format: "W%02d", weekNum)
                : String(format: "W%02d'\(shortYear)", weekNum)

        case .quarter:
            let month = calendar.component(.month, from: point.periodStart)
            let quarter = (month - 1) / 3 + 1
            return pointYear == currentYear ? "Q\(quarter)" : "Q\(quarter)'\(shortYear)"

        case .year:
            return "\(pointYear)"

        case .allTime:
            return point.label
        }
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
        mode: .compact
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
