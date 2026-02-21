//
//  CashFlowChart.swift
//  AIFinanceManager
//
//  Phase 17/18: Financial Insights Feature
//  Area chart showing net cash flow with positive/negative coloring.
//  Phase 18 additions:
//  - PeriodCashFlowChart (granularity-aware, horizontal scroll)
//  - WealthChart for cumulative balance line
//
//  Phase 23-C: Replaced UIScreen.main.bounds with containerRelativeFrame — no UIKit dependency.
//

import SwiftUI
import Charts

// MARK: - CashFlowChart (MonthlyDataPoint — legacy)

struct CashFlowChart: View {
    let dataPoints: [MonthlyDataPoint]
    let currency: String
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }
    /// Phase 18: enable horizontal scroll for large datasets
    var scrollable: Bool = false

    private var lineColor: Color {
        (dataPoints.last?.netFlow ?? 0) >= 0 ? AppColors.success : AppColors.destructive
    }

    private var chartContent: some View {
        Chart(dataPoints) { point in
            AreaMark(
                x: .value("Month", point.month),
                y: .value("Net Flow", point.netFlow)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        point.netFlow >= 0 ? AppColors.success.opacity(0.3) : AppColors.destructive.opacity(0.3),
                        point.netFlow >= 0 ? AppColors.success.opacity(0.05) : AppColors.destructive.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Month", point.month),
                y: .value("Net Flow", point.netFlow)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: isCompact ? 1.5 : 2))

            if !isCompact {
                PointMark(
                    x: .value("Month", point.month),
                    y: .value("Net Flow", point.netFlow)
                )
                .foregroundStyle(point.netFlow >= 0 ? AppColors.success : AppColors.destructive)
                .symbolSize(30)

                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
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
        .frame(height: isCompact ? 60 : 200)
    }

    var body: some View {
        if scrollable && !isCompact && dataPoints.count > 6 {
            // containerRelativeFrame gives the available width without UIScreen dependency
            GeometryReader { proxy in
                let minWidth = proxy.size.width
                let chartWidth = max(minWidth, CGFloat(dataPoints.count) * 50)
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

    private func formatCompact(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if abs >= 1_000     { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

// MARK: - PeriodCashFlowChart (PeriodDataPoint — Phase 18)

/// Granularity-aware cash flow area/line chart.
struct PeriodCashFlowChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    private func chartWidth(containerWidth: CGFloat) -> CGFloat {
        max(containerWidth, CGFloat(dataPoints.count) * pointWidth)
    }

    private var lineColor: Color {
        (dataPoints.last?.netFlow ?? 0) >= 0 ? AppColors.success : AppColors.destructive
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
            AreaMark(
                x: .value("Period", point.label),
                y: .value("Net Flow", point.netFlow)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        lineColor.opacity(0.3),
                        lineColor.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Period", point.label),
                y: .value("Net Flow", point.netFlow)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: isCompact ? 1.5 : 2))

            if !isCompact {
                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Net Flow", point.netFlow)
                )
                .foregroundStyle(point.netFlow >= 0 ? AppColors.success : AppColors.destructive)
                .symbolSize(30)

                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
        .chartXAxis {
            if isCompact {
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
    }

    private func formatCompact(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if abs >= 1_000     { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

// MARK: - WealthChart (cumulative balance — Phase 18)

/// Line chart showing cumulative account balance over time.
/// Uses `cumulativeBalance` from PeriodDataPoint.
struct WealthChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    private func chartWidth(containerWidth: CGFloat) -> CGFloat {
        max(containerWidth, CGFloat(dataPoints.count) * pointWidth)
    }

    private var lineColor: Color { AppColors.accent }

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
            let balance = point.cumulativeBalance ?? point.netFlow

            AreaMark(
                x: .value("Period", point.label),
                y: .value("Balance", balance)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [lineColor.opacity(0.3), lineColor.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Period", point.label),
                y: .value("Balance", balance)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: isCompact ? 1.5 : 2.5))

            if !isCompact {
                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Balance", balance)
                )
                .foregroundStyle(lineColor)
                .symbolSize(25)
            }
        }
        .chartXAxis {
            if isCompact {
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
    }

    private func formatCompact(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if abs >= 1_000     { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }
}

// MARK: - Previews

#Preview("Full cash flow chart (legacy)") {
    CashFlowChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT"
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (card mini-chart)") {
    CashFlowChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT",
        compact: true
    )
    .screenPadding()
    .frame(height: 80)
}

#Preview("PeriodCashFlowChart — Monthly") {
    PeriodCashFlowChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
