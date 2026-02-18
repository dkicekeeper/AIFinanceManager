//
//  SpendingTrendChart.swift
//  AIFinanceManager
//
//  Phase 17/18: Financial Insights Feature
//  Monthly spending trend area/line chart.
//  Phase 18: `scrollable` flag for horizontal scroll support.
//

import SwiftUI
import Charts

struct SpendingTrendChart: View {
    let dataPoints: [MonthlyDataPoint]
    let currency: String
    var compact: Bool = false
    /// Phase 18: wrap in horizontal ScrollView when dataPoints.count exceeds 6
    var scrollable: Bool = false

    private var chartContent: some View {
        innerChart
    }

    private var innerChart: some View {
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
            .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2))

            if !compact {
                PointMark(
                    x: .value("Month", point.month),
                    y: .value("Expenses", point.expenses)
                )
                .foregroundStyle(AppColors.destructive)
                .symbolSize(30)
            }
        }
        .chartXAxis {
            if compact {
                AxisMarks { _ in }   // Hidden in compact mode
            } else {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            if compact {
                AxisMarks { _ in }   // Hidden in compact mode
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
        .frame(height: compact ? 60 : 200)
    }

    var body: some View {
        if scrollable && !compact && dataPoints.count > 6 {
            let minWidth = UIScreen.main.bounds.width - 48
            let chartWidth = max(minWidth, CGFloat(dataPoints.count) * 50)
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
        compact: true
    )
    .screenPadding()
    .frame(height: 80)
}
