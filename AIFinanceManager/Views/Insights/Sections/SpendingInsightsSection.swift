//
//  SpendingInsightsSection.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  Section displaying spending-related insights
//
//  Phase 23: P9 — viewModel replaced with onCategoryTap closure in InsightDetailView.
//  SpendingInsightsSection still holds a viewModel reference to build the closure,
//  but InsightDetailView itself no longer depends on the full ViewModel.
//

import SwiftUI

struct SpendingInsightsSection: View {
    let insights: [Insight]
    let currency: String
    /// Used only to build the onCategoryTap closure for category drill-down.
    var viewModel: InsightsViewModel? = nil

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                ForEach(insights) { insight in
                    NavigationLink(destination: InsightDetailView(
                        insight: insight,
                        currency: currency,
                        onCategoryTap: categoryTapHandler
                    )) {
                        InsightsCardView(insight: insight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Returns an AnyView drill-down destination for a tapped category row, or nil if no viewModel.
    private var categoryTapHandler: ((CategoryBreakdownItem) -> AnyView)? {
        guard let vm = viewModel else { return nil }
        return { item in
            AnyView(
                CategoryDeepDiveView(
                    categoryName: item.categoryName,
                    color: item.color,
                    iconSource: item.iconSource,
                    currency: currency,
                    viewModel: vm
                )
            )
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
