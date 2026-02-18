//
//  RecurringInsightsSection.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Section displaying recurring/subscription insights
//

import SwiftUI

struct RecurringInsightsSection: View {
    let insights: [Insight]
    let currency: String

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

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
            Image(systemName: InsightCategory.recurring.icon)
                .foregroundStyle(AppColors.accent)
            Text(InsightCategory.recurring.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .screenPadding()
    }
}
