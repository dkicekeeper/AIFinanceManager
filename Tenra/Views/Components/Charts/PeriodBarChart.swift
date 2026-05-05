//
//  PeriodBarChart.swift
//  Tenra
//
//  Granularity-aware income/expense grouped bar chart.
//
//  Performance notes (after audit):
//  - Single-tap selection (`chartXSelection(value:)`) is the only selection mode.
//    Range selection was removed: every frame, the range-banner subtree was a
//    body-redraw amplifier, plus the dual `chartXSelection(value:) + (range:)`
//    pair forced two state writes per gesture.
//  - Y-domain is dynamic for the visible window. Lookups use a cached
//    `[label: index]` map (`PeriodBarChartCache`) — replaces O(N)
//    `firstIndex(where:)` that fired on every scroll frame.
//  - Scroll-position binding throttles same-value writes (Apple Charts emits
//    redundant updates during settle).
//  - Localized labels and the axis label map are cached / hoisted out of body
//    to keep the per-frame body cost flat during scroll.
//  - No animations on hot-path state (selection, scroll position, zoom).
//

import SwiftUI
import Charts

/// Per-instance label→index cache. See `PeriodLineChartCache` header for the
/// rationale (avoids O(N) `firstIndex(where:)` on every horizontal-scroll frame).
@MainActor
private final class PeriodBarChartCache {
    var labelToIndex: [String: Int] = [:]
    var labelIndexIdentity: String = ""
}

struct PeriodBarChart: View {
    let dataPoints: [PeriodDataPoint]
    let currency: String
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full

    /// External zoom binding — controlled by `PeriodChartSwitcher` toolbar.
    /// Defaults to 1.0 when the chart is used standalone (no parent toolbar).
    @Binding var zoomScale: CGFloat

    @State private var selectedValueLabel: String?
    @State private var cache = PeriodBarChartCache()

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

    /// Static Y max over the entire dataset. Replaces the previous dynamic
    /// per-window recompute (which caused bars to visually jump when scrolling
    /// across stretches with different magnitudes).
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

    // MARK: Body

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
            icon: "chart.bar",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Period", point.label),
                y: .value("Income", point.income),
                width: .fixed(6)
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.success.opacity(0.85))
            .position(by: .value("Type", "income"))

            BarMark(
                x: .value("Period", point.label),
                y: .value("Expenses", point.expenses),
                width: .fixed(6)
            )
            .cornerRadius(AppRadius.xs)
            .foregroundStyle(AppColors.destructive.opacity(0.85))
            .position(by: .value("Type", "expenses"))
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
                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Income", point.income)
                )
                .cornerRadius(AppRadius.xs)
                .foregroundStyle(AppColors.success.opacity(0.85))
                .position(by: .value("Type", "income"))

                BarMark(
                    x: .value("Period", point.label),
                    y: .value("Expenses", point.expenses)
                )
                .cornerRadius(AppRadius.xs)
                .foregroundStyle(AppColors.destructive.opacity(0.85))
                .position(by: .value("Type", "expenses"))
            }

            // Selection emphasis last — drawn on top.
            // For bar chart: a translucent vertical band highlighting the column,
            // plus a stronger ruler on top of the band centre.
            if let label = selectedValueLabel {
                RectangleMark(x: .value("SelBand", label))
                    .foregroundStyle(AppColors.accent.opacity(0.10))

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(AppColors.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: 0...yMaxNow)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        // Trailing anchor — see PeriodLineChart.
        .chartScrollPosition(initialX: trailingAnchorLabel)
        // Framework-supported selection — coexists with `chartScrollableAxes`.
        .chartXSelection(value: $selectedValueLabel)
        .chartXAxis {
            AxisMarks { value in
                // Greedy collision resolution prevents overlapping date labels
                // when zoomed in (many ticks crammed into narrow visible window).
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
                        FormattedAmountText(
                            amount: point.income,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .regular,
                            color: AppColors.success
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.destructive).frame(width: 8, height: 8)
                        FormattedAmountText(
                            amount: point.expenses,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .regular,
                            color: AppColors.destructive
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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

// MARK: - Previews

#Preview("PeriodBarChart — Monthly") {
    PeriodBarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("PeriodBarChart — Compact") {
    PeriodBarChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        currency: "KZT",
        granularity: .month,
        mode: .compact
    )
    .screenPadding()
    .frame(height: 80)
}
