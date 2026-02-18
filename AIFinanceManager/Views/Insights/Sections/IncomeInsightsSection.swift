//
//  IncomeInsightsSection.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Section displaying income-related insights
//

import SwiftUI

struct IncomeInsightsSection: View {
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
            Image(systemName: InsightCategory.income.icon)
                .foregroundStyle(AppColors.success)
            Text(InsightCategory.income.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .screenPadding()
    }
}
