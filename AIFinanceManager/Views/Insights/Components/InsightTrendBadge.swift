//
//  InsightTrendBadge.swift
//  AIFinanceManager
//
//  Trend indicator badge for Insights cards and detail headers.
//  Extracted from InsightsCardView (pill) and InsightDetailView (inline) — Phase 26.
//

import SwiftUI

/// Compact trend indicator displaying direction icon + percentage change.
///
/// Two styles:
/// - `.pill` — colored semi-transparent Capsule background (InsightsCardView)
/// - `.inline` — flat, no background (InsightDetailView header)
struct InsightTrendBadge: View {
    let trend: InsightTrend

    enum Style {
        /// Colored capsule background.
        case pill
        /// Flat, no background.
        case inline
    }

    var style: Style = .pill

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: trend.trendIcon)
                .font(style == .pill
                      ? AppTypography.caption2.weight(.bold)
                      : AppTypography.bodySmall)

            if let percent = trend.changePercent {
                Text(String(format: "%+.1f%%", percent))
                    .font(style == .pill ? AppTypography.caption2 : AppTypography.bodySmall)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(trend.trendColor)
        .modifier(PillModifier(isActive: style == .pill, color: trend.trendColor))
    }
}

// MARK: - Pill modifier

private struct PillModifier: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview {
    let upTrend = InsightTrend(direction: .up, changePercent: 12.4, changeAbsolute: nil, comparisonPeriod: "vs prev month")
    let downTrend = InsightTrend(direction: .down, changePercent: -5.1, changeAbsolute: nil, comparisonPeriod: "vs prev month")

    return VStack(spacing: AppSpacing.lg) {
        Text("Pill style").font(AppTypography.caption).foregroundStyle(.secondary)
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .pill)
            InsightTrendBadge(trend: downTrend, style: .pill)
        }

        Text("Inline style").font(AppTypography.caption).foregroundStyle(.secondary)
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .inline)
            InsightTrendBadge(trend: downTrend, style: .inline)
        }
    }
    .screenPadding()
}
