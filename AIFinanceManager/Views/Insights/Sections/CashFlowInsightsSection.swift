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
    var periodDataPoints: [PeriodDataPoint] = []
    var granularity: InsightGranularity = .month

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                // Period chart — shown when period data points are available
                if periodDataPoints.count >= 2 {
                    PeriodCashFlowChart(
                        dataPoints: periodDataPoints,
                        currency: currency,
                        granularity: granularity,
                        compact: false
                    )
                    .screenPadding()
                }

                ForEach(insights) { insight in
                    NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                        InsightsCardView(insight: insight)
                    }
                    .buttonStyle(.plain)
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
