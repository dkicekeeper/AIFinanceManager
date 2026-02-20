//
//  CashFlowInsightsSection.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights Feature
//  Section displaying cash flow insights with a scrollable period chart.
//

import SwiftUI

struct CashFlowInsightsSection: View {
    let insights: [Insight]
    let currency: String
    /// Phase 18: period data points for the scrollable chart
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                if periodDataPoints.count >= 2, let firstInsight = insights.first {
                    // First card — PeriodCashFlowChart embedded inside InsightsCardView
                    NavigationLink(destination: InsightDetailView(insight: firstInsight, currency: currency)) {
                        InsightsCardView(insight: firstInsight) {
                            PeriodCashFlowChart(
                                dataPoints: periodDataPoints,
                                currency: currency,
                                granularity: granularity,
                                compact: false
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard (mini chart overlay preserved)
                    ForEach(insights.dropFirst()) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // No period data available — all cards rendered without bottom chart
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
            Image(systemName: InsightCategory.cashFlow.icon)
                .foregroundStyle(AppColors.accent)
            Text(InsightCategory.cashFlow.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .screenPadding()
    }
}
