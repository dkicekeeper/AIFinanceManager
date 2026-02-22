//
//  InsightsSectionView.swift
//  AIFinanceManager
//
//  Universal parameterised section view for Insights.
//  Replaces: IncomeInsightsSection, BudgetInsightsSection, RecurringInsightsSection,
//            SpendingInsightsSection, CashFlowInsightsSection, WealthInsightsSection.
//
//  Usage — simple section (Income, Budget, Recurring):
//      InsightsSectionView(category: .income, insights: insights, currency: currency)
//
//  Usage — section with drill-down (Spending):
//      InsightsSectionView(category: .spending, insights: insights, currency: currency,
//                          onCategoryTap: { item in AnyView(CategoryDeepDiveView(...)) })
//
//  Phase 29 (revised): Full chart removed from section view.
//  All sections show compact mini-chart cards on the main Insights screen.
//  Full charts appear in InsightDetailView when tapping individual insight cards.
//

import SwiftUI

struct InsightsSectionView: View {

    // MARK: - Properties

    let category: InsightCategory
    let insights: [Insight]
    let currency: String
    var onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
    var granularity: InsightGranularity? = nil

    // MARK: - Body

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeaderView(category.displayName, systemImage: category.icon, style: .insights)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .screenPadding()

                // ALL cards use compact mini-charts
                ForEach(insights) { insight in
                    NavigationLink(
                        destination: InsightDetailView(
                            insight: insight,
                            currency: currency,
                            onCategoryTap: onCategoryTap
                        )
                    ) {
                        InsightsCardView(insight: insight)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Simple — Income") {
    NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .income,
                insights: [.mockIncomeGrowth()],
                currency: "KZT"
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Spending — with drill-down") {
    NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .spending,
                insights: [.mockTopSpending(), .mockMoM(), .mockAvgDaily()],
                currency: "KZT",
                onCategoryTap: { item in
                    AnyView(Text("Deep dive: \(item.categoryName)").padding())
                }
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Cash Flow — compact cards only") {
    NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .cashFlow,
                insights: [.mockCashFlow(), .mockProjectedBalance()],
                currency: "KZT"
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}

#Preview("Wealth — compact cards only") {
    NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .wealth,
                insights: [.mockWealthBreakdown()],
                currency: "KZT"
            )
            .padding(.vertical, AppSpacing.md)
        }
    }
}
