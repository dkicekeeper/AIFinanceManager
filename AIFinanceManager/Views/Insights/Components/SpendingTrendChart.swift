//
//  SpendingTrendChart.swift
//  AIFinanceManager
//
//  Phase 17/18: Financial Insights Feature
//  Monthly spending trend area/line chart.
//  Phase 18: `scrollable` flag for horizontal scroll support.
//
//  Phase 27:
//  - Y-axis moved to leading (left) position
//  - Default horizontal scroll position: trailing (most recent data)
//  - X-axis: same compact date formatting as IncomeExpenseChart
//  - Top Y-label clipping fix: padding(.top)
//
//  Phase 28:
//  - Removed local formatCompact / formatAxisDate / axisMonthFormatter → ChartAxisHelpers
//  - Refactored innerChart → mainChart(showYAxis:) + yAxisReferenceChart (ZStack overlay pattern)
//  - Added PeriodSpendingTrendChart — granularity-aware variant using PeriodDataPoint
//

import SwiftUI
import Charts

// MARK: - SpendingTrendChart (MonthlyDataPoint — legacy)

struct SpendingTrendChart: View {
    let dataPoints: [MonthlyDataPoint]
    let currency: String
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }
    /// Phase 18: wrap in horizontal ScrollView when dataPoints.count exceeds 6
    var scrollable: Bool = false

    private var chartHeight: CGFloat { isCompact ? 60 : 200 }

    // MARK: Body

    var body: some View {
        if scrollable && !isCompact && dataPoints.count > 6 {
            GeometryReader { proxy in
                let container = proxy.size.width
                let yAxisWidth: CGFloat = 50
                let scrollWidth = max(container, CGFloat(dataPoints.count) * 50)
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        mainChart(showYAxis: false)
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
            .frame(height: chartHeight)
            .padding(.top, AppSpacing.sm)
        } else {
            mainChart(showYAxis: !isCompact)
        }
    }

    // MARK: - Y-axis reference chart (overlay for scrollable mode)

    private var yAxisReferenceChart: some View {
        Chart(dataPoints) { point in
            LineMark(x: .value("Month", point.month), y: .value("v", point.expenses))
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

    // MARK: - Main chart

    private func mainChart(showYAxis: Bool) -> some View {
        Chart(dataPoints) { point in
            AreaMark(
                x: .value("Month", point.month),
                y: .value("Expenses", point.expenses)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.destructive.opacity(0.3), AppColors.destructive.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Month", point.month),
                y: .value("Expenses", point.expenses)
            )
            .foregroundStyle(AppColors.destructive)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: isCompact ? 1.5 : 2))

            if !isCompact {
                PointMark(
                    x: .value("Month", point.month),
                    y: .value("Expenses", point.expenses)
                )
                .foregroundStyle(AppColors.destructive)
                .symbolSize(30)
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
        .frame(height: chartHeight)
    }
}

// MARK: - PeriodSpendingTrendChart (PeriodDataPoint — Phase 28)

/// Granularity-aware spending trend area/line chart.
/// Single series: `expenses` from `PeriodDataPoint`.
/// Y-axis is pinned to the left (always visible) while content scrolls right.
/// Default scroll position: trailing (most recent data visible on load).
struct PeriodSpendingTrendChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full
    private var isCompact: Bool { mode == .compact }

    private var pointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private let lineColor: Color = AppColors.destructive

    /// Y-scale starts at 0 (expenses are always non-negative).
    private var yDomain: ClosedRange<Double> {
        let maxVal = Swift.max(dataPoints.map { $0.expenses }.max() ?? 0, 1)
        return 0...maxVal
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
            LineMark(x: .value("p", point.label), y: .value("v", point.expenses))
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
                y: .value("Expenses", point.expenses)
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
                y: .value("Expenses", point.expenses)
            )
            .foregroundStyle(lineColor)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: isCompact ? 1.5 : 2))

            if !isCompact {
                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Expenses", point.expenses)
                )
                .foregroundStyle(lineColor)
                .symbolSize(30)
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
        .chartLegend(.hidden)
    }
}

// MARK: - Previews

#Preview("Full spending trend") {
    SpendingTrendChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT"
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (card mini-chart)") {
    SpendingTrendChart(
        dataPoints: MonthlyDataPoint.mockTrend(),
        currency: "KZT",
        mode: .compact
    )
    .screenPadding()
    .frame(height: 80)
}

#Preview("PeriodSpendingTrendChart — Monthly") {
    PeriodSpendingTrendChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("PeriodSpendingTrendChart — Weekly") {
    PeriodSpendingTrendChart(
        dataPoints: PeriodDataPoint.mockWeekly(),
        currency: "KZT",
        granularity: .week
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("PeriodSpendingTrendChart — Compact") {
    PeriodSpendingTrendChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month,
        mode: .compact
    )
    .screenPadding()
    .frame(height: 80)
}
