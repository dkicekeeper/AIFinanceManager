//
//  WealthInsightsSection.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights Feature
//  Section displaying accumulated capital / wealth insights with a cumulative balance chart.
//

import SwiftUI

struct WealthInsightsSection: View {
    let insights: [Insight]
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity
    let currency: String

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                if periodDataPoints.count >= 2, let firstInsight = insights.first {
                    // First card — WealthChart embedded inside InsightsCardView
                    NavigationLink(destination: InsightDetailView(insight: firstInsight, currency: currency)) {
                        InsightsCardView(insight: firstInsight) {
                            WealthChart(
                                dataPoints: periodDataPoints,
                                currency: currency,
                                granularity: granularity,
                                compact: false
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard
                    ForEach(insights.dropFirst()) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // No period data — all cards rendered without bottom chart
                    ForEach(insights) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: InsightCategory.wealth.icon)
                .foregroundStyle(AppColors.accent)
            Text(InsightCategory.wealth.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .screenPadding()
    }
}
