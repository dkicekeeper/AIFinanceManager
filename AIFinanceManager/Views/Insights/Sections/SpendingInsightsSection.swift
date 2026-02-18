//
//  SpendingInsightsSection.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Section displaying spending-related insights
//

import SwiftUI

struct SpendingInsightsSection: View {
    let insights: [Insight]
    let currency: String
    /// Passed through to InsightDetailView so category rows can drill down to CategoryDeepDiveView
    var viewModel: InsightsViewModel? = nil

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                ForEach(insights) { insight in
                    NavigationLink(destination: InsightDetailView(
                        insight: insight,
                        currency: currency,
                        viewModel: viewModel
                    )) {
                        InsightsCardView(insight: insight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: InsightCategory.spending.icon)
                .foregroundStyle(AppColors.destructive)
            Text(InsightCategory.spending.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .screenPadding()
    }
}
