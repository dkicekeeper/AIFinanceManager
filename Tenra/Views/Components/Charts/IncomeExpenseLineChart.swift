//
//  IncomeExpenseLineChart.swift
//  Tenra
//
//  Two-line area chart that overlays income (green) and expenses (red) on the
//  same `PeriodDataPoint` series. Companion to `PeriodBarChart`.
//
//  Performance notes (after audit): see PeriodBarChart.swift header.
//  Same rules: static Y, range-only selection, hot-path body kept lean.
//

import SwiftUI
import Charts

/// See `PeriodLineChartCache` header for rationale.
@MainActor
private final class IncomeExpenseLineChartCache {
    var labelToIndex: [String: Int] = [:]
    var labelIndexIdentity: String = ""
}

struct IncomeExpenseLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full

    @Binding var zoomScale: CGFloat

    @State private var selectedValueLabel: String?
    @State private var cache = IncomeExpenseLineChartCache()

    init(
        dataPoints: [PeriodDataPoint],
        currency: String,
        granularity: InsightGranularity,
        mode: ChartDisplayMode = .full,
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.dataPoints = dataPoints
        self.currency = currency
        self.granularity = granularity
        self.mode = mode
        self._zoomScale = zoomScale
    }

    private var isCompact: Bool { mode == .compact }
    private var basePointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineWidth: CGFloat { isCompact ? 1.5 : 2 }

    private var fullYMax: Double {
        dataPoints.flatMap { [$0.income, $0.expenses] }.max() ?? 1
    }

    private var selectedSinglePoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

    /// Width-independent visible-window size. See PeriodLineChart for rationale.
    private var visibleCount: Int {
        let base = 12.0
        let raw = Int((base / max(zoomScale, 0.1)).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    private var todayLabel: String? {
        let now = Date()
        return dataPoints.first(where: { $0.periodStart > now })?.label
    }

    private var dataPointsIdentity: String {
        guard let first = dataPoints.first, let last = dataPoints.last else { return "" }
        return "\(dataPoints.count)|\(first.label)|\(last.label)"
    }

    private func rebuildLabelIndexIfNeeded() {
        let identity = dataPointsIdentity
        guard cache.labelIndexIdentity != identity else { return }
        var map = [String: Int]()
        map.reserveCapacity(dataPoints.count)
        for (i, p) in dataPoints.enumerated() { map[p.label] = i }
        cache.labelToIndex = map
        cache.labelIndexIdentity = identity
    }

    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
    }

    var body: some View {
        if dataPoints.isEmpty {
            emptyState.frame(height: chartHeight)
        } else if isCompact {
            // See PeriodLineChart — `.chartAppear()` removed for compact (scroll cost).
            sparkline
                .frame(height: chartHeight)
        } else {
            VStack(spacing: AppSpacing.sm) {
                bannerSlot

                fullChart
                    .frame(height: chartHeight)
            }
            .onChange(of: selectedValueLabel) { _, new in
                guard new != nil else { return }
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .onAppear { rebuildLabelIndexIfNeeded() }
            .onChange(of: dataPointsIdentity) { _, _ in rebuildLabelIndexIfNeeded() }
            .chartAppear()
        }
    }

    /// Fixed-height slot — see PeriodLineChart.bannerSlot for rationale.
    private var bannerSlot: some View {
        ZStack {
            if let p = selectedSinglePoint {
                singleBanner(point: p)
                    .transition(.opacity)
            }
        }
        .frame(height: 56)
        .screenPadding()
        .animation(.easeInOut(duration: 0.15), value: selectedSinglePoint?.label)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "chart.xyaxis.line",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                series: .value("Type", "income")
            )
            .foregroundStyle(AppColors.success)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))

            LineMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                series: .value("Type", "expenses")
            )
            .foregroundStyle(AppColors.destructive)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
        .chartYScale(domain: 0...fullYMax)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis { AxisMarks { _ in } }
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Interactive full chart

    private var fullChart: some View {
        let yMaxNow = fullYMax
        let categoryDomain = dataPoints.map { $0.label }
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
        return Chart {
            // Today marker — drawn first; today is always part of dataPoints'
            // label set so it doesn't introduce a new category.
            if let today = todayLabel {
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(AppColors.accent.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text(String(localized: "insights.today"))
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.accent)
                    }
            }

            ForEach(dataPoints) { point in
                // Both `series:` AND `stacking: .unstacked` are required:
                //   • `series:` ensures Apple Charts treats income and expenses as
                //     two distinct lines/areas (without it, alternating x-values
                //     would merge into a single zig-zag).
                //   • `stacking: .unstacked` keeps each area baseline at y=0 instead
                //     of stacking expense on top of income (which would inflate
                //     the visible expense area beyond its actual value).
                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income),
                    series: .value("Type", "income"),
                    stacking: .unstacked
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.25), AppColors.success.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income),
                    series: .value("Type", "income")
                )
                .foregroundStyle(AppColors.success)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.income)
                )
                .foregroundStyle(AppColors.success)
                .symbolSize(28)

                AreaMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses),
                    series: .value("Type", "expenses"),
                    stacking: .unstacked
                )
                .foregroundStyle(LinearGradient(
                    colors: [AppColors.destructive.opacity(0.25), AppColors.destructive.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses),
                    series: .value("Type", "expenses")
                )
                .foregroundStyle(AppColors.destructive)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))

                PointMark(
                    x: .value("Period", point.label),
                    y: .value("Amount", point.expenses)
                )
                .foregroundStyle(AppColors.destructive)
                .symbolSize(28)
            }

            // Selection emphasis last. Two-series chart so we highlight BOTH the
            // income and expense points at the selected x. See PeriodLineChart
            // for the visual layering rationale (ruler → halo → inner).
            if let label = selectedValueLabel,
               let idx = cache.labelToIndex[label] {
                let p = dataPoints[idx]

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(x: .value("SelHaloIn", p.label), y: .value("V", p.income))
                    .symbolSize(180)
                    .foregroundStyle(AppColors.success.opacity(0.20))
                PointMark(x: .value("SelInnerIn", p.label), y: .value("V", p.income))
                    .symbolSize(70)
                    .foregroundStyle(AppColors.success)

                PointMark(x: .value("SelHaloEx", p.label), y: .value("V", p.expenses))
                    .symbolSize(180)
                    .foregroundStyle(AppColors.destructive.opacity(0.20))
                PointMark(x: .value("SelInnerEx", p.label), y: .value("V", p.expenses))
                    .symbolSize(70)
                    .foregroundStyle(AppColors.destructive)
            }
        }
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        // Trailing anchor — see PeriodLineChart.
        .chartScrollPosition(initialX: trailingAnchorLabel)
        // Framework-supported selection — see PeriodLineChart for rationale.
        .chartXSelection(value: $selectedValueLabel)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6)) {
                    if let label = value.as(String.self) {
                        Text(axisLabelMap[label] ?? label)
                            .font(AppTypography.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(ChartAxisHelpers.formatCompact(amount))
                            .font(AppTypography.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }

    // MARK: - Single-point banner

    /// Selection banner. No close button — auto-hides on tap-off / scroll.
    /// Date is emphasised; income/expenses shown side by side beneath.
    private func singleBanner(point: PeriodDataPoint) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(axisLabelMap[point.label] ?? point.label)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                HStack(spacing: AppSpacing.md) {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.success).frame(width: 8, height: 8)
                        Text(ChartAxisHelpers.formatCompact(point.income))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.success)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.destructive).frame(width: 8, height: 8)
                        Text(ChartAxisHelpers.formatCompact(point.expenses))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.destructive)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .cardStyle()
    }

}

#Preview("IncomeExpenseLineChart — Monthly") {
    IncomeExpenseLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
