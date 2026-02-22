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
//  Phase 27:
//  - Y-axis moved to leading overlay (always visible while scrolling)
//  - Default horizontal scroll position: trailing (most recent data)
//  - X-axis: same compact date formatting as IncomeExpenseChart
//  - Legacy charts: formatAxisDate applied to CashFlowChart
//
//  Phase 28:
//  - Removed local formatCompact / formatAxisDate / axisMonthFormatter → ChartAxisHelpers
//  - Removed local axisLabelMap / compactPeriodLabel → ChartAxisHelpers (PeriodCashFlowChart, WealthChart)
//  - CashFlowChart: scrollable branch refactored to ZStack Y-axis overlay
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

    // MARK: Body

    var body: some View {
        if scrollable && !isCompact && dataPoints.count > 6 {
            GeometryReader { proxy in
                let container = proxy.size.width
                let yAxisWidth: CGFloat = 50
                let scrollWidth = max(container, CGFloat(dataPoints.count) * 50)
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        chartContent(showYAxis: false)
                            .frame(width: scrollWidth, height: 200)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.trailing)

                    // Y-axis overlay — always visible, doesn't scroll with chart
                    yAxisReferenceChart
                        .frame(width: yAxisWidth, height: 200)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 200)
            .padding(.top, AppSpacing.sm)
        } else {
            chartContent(showYAxis: !isCompact)
        }
    }

    // MARK: - Y-axis reference chart (overlay for scrollable mode)

    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            LineMark(x: .value("Month", point.month), y: .value("v", point.netFlow))
                .opacity(0)
        }
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    // MARK: - Chart content

    private func chartContent(showYAxis: Bool) -> some View {
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
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(ChartAxisHelpers.formatAxisDate(date))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if isCompact {
                AxisMarks { _ in }
            } else if showYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(ChartAxisHelpers.formatCompact(amount))
                                .font(AppTypography.caption2)
                        }
                    }
                }
            } else {
                // Grid lines only — Y labels handled by yAxisReferenceChart overlay
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel { EmptyView() }
                }
            }
        }
        .frame(height: isCompact ? 60 : 200)
    }
}

// MARK: - PeriodCashFlowChart (PeriodDataPoint — Phase 18)

/// Granularity-aware cash flow area/line chart.
/// Y-axis is pinned to the left (always visible) while content scrolls right.
/// Default scroll position: trailing (most recent data visible on load).
struct PeriodCashFlowChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    private var lineColor: Color {
        (dataPoints.last?.netFlow ?? 0) >= 0 ? AppColors.success : AppColors.destructive
    }

    /// Y-scale domain computed from data — ensures Y-axis and main chart are in sync.
    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.netFlow }
        let minVal = Swift.min(values.min() ?? 0, 0)
        let maxVal = Swift.max(values.max() ?? 0, 1)
        return minVal...maxVal
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size.width
            let yAxisWidth: CGFloat = 50

            if isCompact {
                mainChart
                    .frame(width: container, height: chartHeight)
            } else {
                let scrollWidth = max(
                    container,
                    CGFloat(dataPoints.count) * pointWidth
                )
                ZStack(alignment: .topLeading) {
                    // Scrollable chart content
                    ScrollView(.horizontal, showsIndicators: false) {
                        mainChart
                            .frame(width: scrollWidth, height: chartHeight)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.trailing)

                    // Y-axis overlay — always visible, doesn't scroll with chart
                    yAxisReferenceChart
                        .frame(width: yAxisWidth, height: chartHeight)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: chartHeight)
        .padding(.top, isCompact ? 0 : AppSpacing.sm)
    }

    // MARK: - Y-axis reference chart

    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            LineMark(x: .value("p", point.label), y: .value("v", point.netFlow))
                .opacity(0)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    // MARK: - Main chart

    private var mainChart: some View {
        let labelMap = ChartAxisHelpers.axisLabelMap(for: dataPoints)
        return Chart(dataPoints) { point in
            AreaMark(
                x: .value("Period", point.label),
                y: .value("Net Flow", point.netFlow)
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
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(labelMap[label] ?? label)
                                .font(AppTypography.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            // Grid lines only — labels handled by yAxisReferenceChart
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { _ in
                    AxisGridLine()
                }
            }
        }
    }
}

// MARK: - WealthChart (cumulative balance — Phase 18)

/// Line chart showing cumulative account balance over time.
/// Y-axis is pinned to the left (always visible) while content scrolls right.
/// Default scroll position: trailing (most recent data visible on load).
struct WealthChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineColor: Color { AppColors.accent }

    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.cumulativeBalance ?? $0.netFlow }
        let minVal = Swift.min(values.min() ?? 0, 0)
        let maxVal = Swift.max(values.max() ?? 0, 1)
        return minVal...maxVal
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size.width
            let yAxisWidth: CGFloat = 50

            if isCompact {
                mainChart
                    .frame(width: container, height: chartHeight)
            } else {
                let scrollWidth = max(
                    container,
                    CGFloat(dataPoints.count) * pointWidth
                )
                ZStack(alignment: .topLeading) {
                    // Scrollable chart content
                    ScrollView(.horizontal, showsIndicators: false) {
                        mainChart
                            .frame(width: scrollWidth, height: chartHeight)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.trailing)

                    // Y-axis overlay — always visible, doesn't scroll with chart
                    yAxisReferenceChart
                        .frame(width: yAxisWidth, height: chartHeight)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: chartHeight)
        .padding(.top, isCompact ? 0 : AppSpacing.sm)
    }

    // MARK: - Y-axis reference chart

    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            let balance = point.cumulativeBalance ?? point.netFlow
            LineMark(x: .value("p", point.label), y: .value("v", balance))
                .opacity(0)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
    }

    // MARK: - Main chart

    private var mainChart: some View {
        let labelMap = ChartAxisHelpers.axisLabelMap(for: dataPoints)
        return Chart(dataPoints) { point in
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
        .chartYScale(domain: yDomain)
        .chartXAxis {
            if isCompact {
                AxisMarks { _ in }
            } else {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(labelMap[label] ?? label)
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
                AxisMarks { _ in
                    AxisGridLine()
                }
            }
        }
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
        mode: .compact
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

#Preview("WealthChart — Monthly") {
    WealthChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
