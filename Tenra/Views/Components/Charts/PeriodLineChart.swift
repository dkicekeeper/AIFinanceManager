//
//  PeriodLineChart.swift
//  Tenra
//
//  Phase 43 (chart merge): Unified granularity-aware area/line chart.
//  Replaces three structurally identical components:
//  - PeriodSpendingTrendChart (expenses, 0-based Y, destructive color)
//  - PeriodCashFlowChart     (netFlow, ±Y, dynamic green/red, zero ruler)
//  - WealthChart             (cumulativeBalance, ±Y, accent color)
//
//  Behavioral differences are captured in PeriodLineChartSeries enum.
//  Layout, scrolling, Y-axis overlay, and animation are shared.
//

import SwiftUI
import Charts

// MARK: - PeriodLineChartSeries

/// Defines which data field and visual style a `PeriodLineChart` uses.
enum PeriodLineChartSeries {
    /// Spending trend: `expenses` field, Y starts at 0, destructive color.
    case spending
    /// Cash flow: `netFlow` field, ± Y, color tracks direction, zero reference line.
    case cashFlow
    /// Wealth: `cumulativeBalance` field (falls back to `netFlow`), ± Y, accent color.
    case wealth

    // MARK: - Data extraction

    func value(for point: PeriodDataPoint) -> Double {
        switch self {
        case .spending: return point.expenses
        case .cashFlow: return point.netFlow
        case .wealth:   return point.cumulativeBalance ?? point.netFlow
        }
    }

    // MARK: - Y-domain

    func yDomain(values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .spending:
            return 0...Swift.max(values.max() ?? 0, 1)
        case .cashFlow, .wealth:
            let min = Swift.min(values.min() ?? 0, 0)
            let max = Swift.max(values.max() ?? 0, 1)
            return min...max
        }
    }

    // MARK: - Colors

    /// Per-point color used for PointMark (cashFlow colors each point individually).
    func pointColor(for value: Double) -> Color {
        switch self {
        case .spending: return AppColors.destructive
        case .cashFlow: return value >= 0 ? AppColors.success : AppColors.destructive
        case .wealth:   return AppColors.accent
        }
    }

    /// Line stroke style. For `.cashFlow` produces a vertical green→red gradient
    /// with the transition pinned to y=0, so the line color smoothly tracks the
    /// sign of each point along the curve. For other series returns a solid color.
    func lineStyle(yDomain: ClosedRange<Double>) -> AnyShapeStyle {
        switch self {
        case .spending: return AnyShapeStyle(AppColors.destructive)
        case .wealth:   return AnyShapeStyle(AppColors.accent)
        case .cashFlow:
            let total = yDomain.upperBound - yDomain.lowerBound
            guard total > 0 else { return AnyShapeStyle(AppColors.success) }
            let zeroRatio = (yDomain.upperBound - 0) / total
            if zeroRatio <= 0 { return AnyShapeStyle(AppColors.destructive) }
            if zeroRatio >= 1 { return AnyShapeStyle(AppColors.success) }
            let eps = 0.001
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: AppColors.success,     location: 0),
                    .init(color: AppColors.success,     location: max(0, zeroRatio - eps)),
                    .init(color: AppColors.destructive, location: min(1, zeroRatio + eps)),
                    .init(color: AppColors.destructive, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    /// Area fill style. Mirrors `lineStyle` but with reduced opacity. For `.cashFlow`
    /// the gradient flips opacity above and below zero so each side reads as a tinted area.
    func areaStyle(yDomain: ClosedRange<Double>) -> AnyShapeStyle {
        switch self {
        case .spending:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.destructive.opacity(0.3), AppColors.destructive.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
        case .wealth:
            return AnyShapeStyle(LinearGradient(
                colors: [AppColors.accent.opacity(0.3), AppColors.accent.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
        case .cashFlow:
            let total = yDomain.upperBound - yDomain.lowerBound
            guard total > 0 else {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.3), AppColors.success.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            let zeroRatio = (yDomain.upperBound - 0) / total
            if zeroRatio <= 0 {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.destructive.opacity(0.05), AppColors.destructive.opacity(0.3)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            if zeroRatio >= 1 {
                return AnyShapeStyle(LinearGradient(
                    colors: [AppColors.success.opacity(0.3), AppColors.success.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            let eps = 0.001
            return AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: AppColors.success.opacity(0.35),     location: 0),
                    .init(color: AppColors.success.opacity(0.05),     location: max(0, zeroRatio - eps)),
                    .init(color: AppColors.destructive.opacity(0.05), location: min(1, zeroRatio + eps)),
                    .init(color: AppColors.destructive.opacity(0.35), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    // MARK: - Visual flags

    /// Whether to render a dashed zero reference line (RuleMark at y=0).
    var showZeroRuler: Bool {
        switch self {
        case .spending, .wealth: return false
        case .cashFlow:          return true
        }
    }

    /// Line width in full (non-compact) mode.
    var fullLineWidth: CGFloat {
        switch self {
        case .spending, .cashFlow: return 2
        case .wealth:              return 2.5
        }
    }
}

// MARK: - PeriodLineChart

/// Granularity-aware area/line chart for any `PeriodDataPoint` series.
///
/// Full mode uses native Apple Charts horizontal scrolling (`chartScrollableAxes`)
/// with a sticky leading Y-axis. The visible window is controlled by `zoomScale`
/// (1.0 = default), driven by a pinch gesture clamped to `[0.4, 4.0]`.
/// Long-press-and-drag on the chart selects an X range — the chart shows a
/// banner above with the aggregated value (sum/delta) and a reset button.
///
/// Compact mode is a static sparkline — no scrolling, zoom, or selection.
///
/// Usage:
/// ```swift
/// PeriodLineChart(dataPoints: points, series: .cashFlow, granularity: .month)
/// PeriodLineChart(dataPoints: points, series: .wealth,   granularity: .month, mode: .compact)
/// ```
/// Per-instance label→index cache for O(1) lookup when finding a tapped point.
/// Stored as `@State` so the same instance lives across body re-evals; mutating
/// its stored fields is safe — SwiftUI tracks reference identity, not internal
/// class state. Rebuilt only when the dataset's identity fingerprint changes.
@MainActor
private final class PeriodLineChartCache {
    var labelToIndex: [String: Int] = [:]
    var labelIndexIdentity: String = ""
}

struct PeriodLineChart: View {
    let dataPoints: [PeriodDataPoint]
    let series: PeriodLineChartSeries
    let granularity: InsightGranularity
    var mode: ChartDisplayMode = .full

    @State private var zoomScale: CGFloat = 1.0
    @State private var selectedValueLabel: String?
    @State private var cache = PeriodLineChartCache()

    private var isCompact: Bool { mode == .compact }
    private var basePointWidth: CGFloat { isCompact ? 30 : granularity.pointWidth }
    private var effectivePointWidth: CGFloat { basePointWidth * zoomScale }
    private var chartHeight: CGFloat { isCompact ? 60 : 200 }
    private var lineWidth: CGFloat { isCompact ? 1.5 : series.fullLineWidth }

    private var values: [Double] { dataPoints.map { series.value(for: $0) } }

    /// Static Y-domain computed once over the entire dataset. Replaces the previous
    /// `dynamicYDomain(visibleCount:)` which recomputed per body re-eval driven by
    /// scroll position. Two reasons to make it static:
    ///   1. **Visual stability**: with dynamic domain, the Y axis re-scaled as the
    ///      user scrolled — bars/lines visually jumped under their finger.
    ///   2. **Performance**: a stable domain means `lineStyle`/`areaStyle`
    ///      (multi-stop `LinearGradient` for `.cashFlow`/`.wealth`) are constant
    ///      and can be hoisted out of the per-frame body.
    private var fullYDomain: ClosedRange<Double> { series.yDomain(values: values) }

    /// Single-tap selected point.
    private var selectedSinglePoint: PeriodDataPoint? {
        guard let label = selectedValueLabel,
              let idx = cache.labelToIndex[label] else { return nil }
        return dataPoints[idx]
    }

    /// How many data points fit in the visible window. Width-independent: a
    /// category x-axis treats `chartXVisibleDomain(length:)` as "show N
    /// categories regardless of width", so we don't need a `GeometryReader`.
    /// Default = 12 buckets (1 year of months / 3 months of weeks); zoom-in
    /// halves, zoom-out doubles. Apple Charts gracefully clamps small datasets.
    private var visibleCount: Int {
        let base = 12.0
        let raw = Int((base / max(zoomScale, 0.1)).rounded())
        return max(1, min(dataPoints.count, raw))
    }

    /// Label of the first point whose period starts in the future. Nil if all data is in the past.
    private var todayLabel: String? {
        let now = Date()
        return dataPoints.first(where: { $0.periodStart > now })?.label
    }

    /// Identity fingerprint used to detect when `dataPoints` has changed and the
    /// `[label: index]` cache must be rebuilt. Cheap to compute — no full scan.
    private var dataPointsIdentity: String {
        guard let first = dataPoints.first, let last = dataPoints.last else { return "" }
        return "\(dataPoints.count)|\(first.label)|\(last.label)"
    }

    /// Rebuilds the label→index cache when the dataset identity changes.
    /// Side-effecting on the class-typed cache is safe: SwiftUI tracks @State
    /// reference identity, not the class's internal state.
    private func rebuildLabelIndexIfNeeded() {
        let identity = dataPointsIdentity
        guard cache.labelIndexIdentity != identity else { return }
        var map = [String: Int]()
        map.reserveCapacity(dataPoints.count)
        for (i, p) in dataPoints.enumerated() { map[p.label] = i }
        cache.labelToIndex = map
        cache.labelIndexIdentity = identity
    }


    // MARK: Body

    var body: some View {
        if dataPoints.isEmpty {
            emptyState
                .frame(height: chartHeight)
        } else if isCompact {
            // No `.chartAppear()` in compact: mini-charts live in the Insights feed
            // where many materialise simultaneously during scroll — concurrent springs
            // cost frames. Full mode (below) keeps the entrance animation.
            sparkline
                .frame(height: chartHeight)
        } else {
            VStack(spacing: AppSpacing.sm) {
                zoomToolbar
                    .screenPadding()

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

    /// Fixed-height slot for the selection banner. Always reserves space so the
    /// chart below doesn't shift when the banner appears/disappears. Visibility
    /// is opacity-driven; horizontal padding aligns the banner with the screen
    /// margin (`screenPadding`).
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
            icon: "chart.line.uptrend.xyaxis",
            title: String(localized: "insights.empty.title"),
            description: String(localized: "insights.empty.subtitle"),
            style: .compact
        )
    }

    /// Trailing-aligned zoom controls. Pinch-to-zoom was removed because it
    /// conflicted with the parent NavigationStack's swipe-to-go-back gesture.
    private var zoomToolbar: some View {
        HStack {
            Spacer()
            ChartZoomControls(zoomScale: $zoomScale, range: 0.4...4.0)
        }
    }

    // MARK: - Compact sparkline

    private var sparkline: some View {
        let domain = fullYDomain
        let lineFill = series.lineStyle(yDomain: domain)
        let areaFill = series.areaStyle(yDomain: domain)
        return Chart(dataPoints) { point in
            let v = series.value(for: point)
            AreaMark(x: .value("Period", point.label), y: .value("Value", v))
                .foregroundStyle(areaFill)
                .interpolationMethod(.monotone)
            LineMark(x: .value("Period", point.label), y: .value("Value", v))
                .foregroundStyle(lineFill)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
        .chartYScale(domain: domain)
        .chartXAxis { AxisMarks { _ in } }
        .chartYAxis { AxisMarks { _ in } }
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Interactive full chart

    private var fullChart: some View {
        let domain = fullYDomain
        // Stable styles: yDomain is fixed for the lifetime of this view, so the
        // multi-stop `LinearGradient` for `.cashFlow`/`.wealth` is computed once.
        let lineFill = series.lineStyle(yDomain: domain)
        let areaFill = series.areaStyle(yDomain: domain)
        let categoryDomain = dataPoints.map { $0.label }
        // Trailing anchor: leftmost visible label = `count - visibleCount`, so the
        // most recent data appears on the right edge by default.
        let leftIdx = max(0, dataPoints.count - visibleCount)
        let trailingAnchorLabel = dataPoints[leftIdx].label
        return Chart {
            // Today / future boundary marker — drawn first; today is part of
            // dataPoints' label set so this doesn't introduce a new category.
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
                let v = series.value(for: point)
                AreaMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(areaFill)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(lineFill)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth))
                PointMark(x: .value("Period", point.label), y: .value("Value", v))
                    .foregroundStyle(series.pointColor(for: v))
                    .symbolSize(30)
            }

            if series.showZeroRuler {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }

            // Selection emphasis — drawn LAST so it renders on top. The x-domain
            // is also locked via `chartXScale(domain:)` below. Both safeguards
            // ensure selection marks cannot reorder the X axis.
            //
            // Visual layers (back-to-front): ruler → halo → emphasized point.
            if let label = selectedValueLabel,
               let idx = cache.labelToIndex[label] {
                let selectedPoint = dataPoints[idx]
                let v = series.value(for: selectedPoint)
                let pointColor = series.pointColor(for: v)

                RuleMark(x: .value("Selected", label))
                    .foregroundStyle(pointColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(
                    x: .value("SelectedHalo", selectedPoint.label),
                    y: .value("SelectedV", v)
                )
                .symbolSize(180)
                .foregroundStyle(pointColor.opacity(0.20))

                PointMark(
                    x: .value("SelectedInner", selectedPoint.label),
                    y: .value("SelectedV", v)
                )
                .symbolSize(70)
                .foregroundStyle(pointColor)
            }
        }
        // Lock category order to the dataPoints' label sequence. Without this,
        // Apple Charts derives x-domain from "first occurrence across marks in
        // declaration order" — which made the selection RuleMark's label define
        // the leading category, flipping the axis on every tap.
        .chartXScale(domain: categoryDomain)
        .chartYScale(domain: domain)
        .chartXVisibleDomain(length: visibleCount)
        .chartScrollableAxes(.horizontal)
        // Trailing anchor — start with most recent data on the right.
        // `initialX` is one-shot at first appearance and not re-applied on body
        // re-evals (verified by virtue of the architecture: no other anchor
        // sources exist now to compete with it).
        .chartScrollPosition(initialX: trailingAnchorLabel)
        // Use the framework-supported selection. `chartXSelection(value:)`
        // coexists with `chartScrollableAxes` at the gesture-arbitration level —
        // tap selects, drag scrolls.
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

    /// Selection banner. No close button — the banner auto-hides when the user
    /// taps elsewhere or scrolls (selection clears on tap-off via Apple Charts).
    /// Date is emphasised (bodyEmphasis on primary text) per design spec.
    private func singleBanner(point: PeriodDataPoint) -> some View {
        let value = series.value(for: point)
        return HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(axisLabelMap[point.label] ?? point.label)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                Text(ChartAxisHelpers.formatCompact(value))
                    .font(AppTypography.body)
                    .foregroundStyle(series.pointColor(for: value))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .cardStyle()
    }

    // MARK: - Cached axis label map

    /// Built once per `dataPoints` array — survives every body re-eval driven by
    /// gesture/scroll state. Without this cache the dictionary was rebuilt at 60 fps
    /// during pinch/scroll, which dominated the frame budget on real devices.
    private var axisLabelMap: [String: String] {
        ChartAxisLabelMapCache.shared.map(for: dataPoints)
    }
}

// MARK: - Previews

#Preview("Spending — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .spending,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Cash Flow — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .cashFlow,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Wealth — Monthly") {
    PeriodLineChart(
        dataPoints: PeriodDataPoint.mockMonthly(),
        series: .wealth,
        granularity: .month
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact — all series") {
    VStack(spacing: AppSpacing.md) {
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .spending, granularity: .month, mode: .compact)
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .cashFlow, granularity: .month, mode: .compact)
        PeriodLineChart(dataPoints: PeriodDataPoint.mockMonthly(), series: .wealth, granularity: .month, mode: .compact)
    }
    .screenPadding()
    .frame(height: 280)
}
