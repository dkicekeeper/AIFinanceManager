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
//  Usage — section with embedded chart (CashFlow, Wealth):
//      InsightsSectionView(
//          category: .cashFlow, insights: insights, currency: currency,
//          periodDataPoints: points, granularity: .month
//      ) {
//          PeriodCashFlowChart(dataPoints: points, currency: currency,
//                              granularity: .month, compact: false)
//      }
//

import SwiftUI

struct InsightsSectionView<FirstChart: View>: View {

    // MARK: - Properties

    let category: InsightCategory
    let insights: [Insight]
    let currency: String
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity
    var onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
    @ViewBuilder private let firstCardChart: () -> FirstChart

    // MARK: - Init (simple — no embedded chart)
    //
    // Covers: .income, .budget, .recurring, .spending (via onCategoryTap)

    init(
        category: InsightCategory,
        insights: [Insight],
        currency: String,
        onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
    ) where FirstChart == EmptyView {
        self.category = category
        self.insights = insights
        self.currency = currency
        self.periodDataPoints = []
        self.granularity = .month
        self.onCategoryTap = onCategoryTap
        self.firstCardChart = { EmptyView() }
    }

    // MARK: - Init (with embedded chart in the first card)
    //
    // Covers: .cashFlow (PeriodCashFlowChart), .wealth (WealthChart)

    init(
        category: InsightCategory,
        insights: [Insight],
        currency: String,
        periodDataPoints: [PeriodDataPoint],
        granularity: InsightGranularity,
        @ViewBuilder firstCardChart: @escaping () -> FirstChart
    ) {
        self.category = category
        self.insights = insights
        self.currency = currency
        self.periodDataPoints = periodDataPoints
        self.granularity = granularity
        self.onCategoryTap = nil
        self.firstCardChart = firstCardChart
    }

    // MARK: - Computed

    /// `true` when `FirstChart` is not `EmptyView` — a chart was injected via init.
    private var hasChart: Bool {
        FirstChart.self != EmptyView.self
    }

    // MARK: - Body

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                InsightsSectionHeader(category: category)

                if hasChart, let firstInsight = insights.first, periodDataPoints.count >= 2 {
                    // First card — injected chart embedded inside InsightsCardView
                    NavigationLink(
                        destination: InsightDetailView(
                            insight: firstInsight,
                            currency: currency
                        )
                    ) {
                        InsightsCardView(insight: firstInsight) {
                            firstCardChart()
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard (mini-chart overlay preserved)
                    ForEach(insights.dropFirst()) { insight in
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
                } else {
                    // No period data or no chart injected — all cards standard
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
}
