//
//  InsightsView.swift
//  AIFinanceManager
//
//  Phase 23: Insights Performance & UI fixes
//  - P6: removed duplicate onChange(of: selectedGranularity) — picker's onSelect callback suffices
//  - P7: InsightsSummaryHeader now receives PeriodDataPoint directly (no per-render conversion)
//  - Loading / empty state kept; sections unchanged
//

import SwiftUI

struct InsightsView: View {
    // MARK: - Dependencies

    let insightsViewModel: InsightsViewModel

    // MARK: - State

    @State private var selectedGranularity: InsightGranularity = .month

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                if insightsViewModel.isLoading {
                    loadingView
                } else if !insightsViewModel.hasData {
                    emptyState
                } else {
                    // Summary header — tappable, navigates to full period breakdown
                    // P7: pass PeriodDataPoint directly — no per-render .map { asMonthlyDataPoint() }
                    NavigationLink(destination: InsightsSummaryDetailView(
                        totalIncome: insightsViewModel.totalIncome,
                        totalExpenses: insightsViewModel.totalExpenses,
                        netFlow: insightsViewModel.netFlow,
                        currency: insightsViewModel.baseCurrency,
                        periodDataPoints: insightsViewModel.periodDataPoints,
                        granularity: insightsViewModel.currentGranularity
                    )) {
                        InsightsSummaryHeader(
                            totalIncome: insightsViewModel.totalIncome,
                            totalExpenses: insightsViewModel.totalExpenses,
                            netFlow: insightsViewModel.netFlow,
                            currency: insightsViewModel.baseCurrency,
                            periodDataPoints: insightsViewModel.periodDataPoints
                        )
                        .screenPadding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Granularity picker (replaces TimeFilter sheet)
                    InsightsGranularityPicker(selected: $selectedGranularity) { granularity in
                        insightsViewModel.switchGranularity(granularity)
                    }

                    // Category filter
                    categoryFilterCarousel

                    // Insight sections
                    insightSections
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "insights.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    HapticManager.light()
                    insightsViewModel.refreshInsights()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            insightsViewModel.onAppear()
        }
        // P6: onChange removed — InsightsGranularityPicker.onSelect already calls switchGranularity.
        // Keeping both caused double switchGranularity call on every picker tap.
    }

    // MARK: - Category Filter Carousel

    private var categoryFilterCarousel: some View {
        UniversalCarousel(config: .filter) {
            // "All" filter
            UniversalFilterButton(
                title: String(localized: "insights.all"),
                isSelected: insightsViewModel.selectedCategory == nil,
                showChevron: false,
                onTap: {
                    HapticManager.light()
                    insightsViewModel.selectCategory(nil)
                }
            ) {
                Image(systemName: "square.grid.2x2")
            }

            // Category filters
            ForEach(InsightCategory.allCases, id: \.self) { category in
                UniversalFilterButton(
                    title: category.displayName,
                    isSelected: insightsViewModel.selectedCategory == category,
                    showChevron: false,
                    onTap: {
                        HapticManager.light()
                        insightsViewModel.selectCategory(
                            insightsViewModel.selectedCategory == category ? nil : category
                        )
                    }
                ) {
                    Image(systemName: category.icon)
                }
            }
        }
    }

    // MARK: - Insight Sections

    @ViewBuilder
    private var insightSections: some View {
        let filtered = insightsViewModel.filteredInsights

        if filtered.isEmpty {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: AppIconSize.xxxl))
                    .foregroundStyle(AppColors.textTertiary)
                Text(String(localized: "insights.noInsightsForFilter"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xxxl)
        } else if insightsViewModel.selectedCategory == nil {
            // Show all sections
            SpendingInsightsSection(
                insights: insightsViewModel.spendingInsights,
                currency: insightsViewModel.baseCurrency,
                viewModel: insightsViewModel
            )

            IncomeInsightsSection(
                insights: insightsViewModel.incomeInsights,
                currency: insightsViewModel.baseCurrency
            )

            BudgetInsightsSection(
                insights: insightsViewModel.budgetInsights,
                currency: insightsViewModel.baseCurrency
            )

            RecurringInsightsSection(
                insights: insightsViewModel.recurringInsights,
                currency: insightsViewModel.baseCurrency
            )

            CashFlowInsightsSection(
                insights: insightsViewModel.cashFlowInsights,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            )

            // Phase 18 — Wealth section
            if !insightsViewModel.wealthInsights.isEmpty {
                WealthInsightsSection(
                    insights: insightsViewModel.wealthInsights,
                    periodDataPoints: insightsViewModel.periodDataPoints,
                    granularity: insightsViewModel.currentGranularity,
                    currency: insightsViewModel.baseCurrency
                )
            }
        } else {
            // Show filtered insights without section headers
            ForEach(filtered) { insight in
                NavigationLink(destination: InsightDetailView(insight: insight, currency: insightsViewModel.baseCurrency)) {
                    InsightsCardView(insight: insight)
                }
                .buttonStyle(.plain)
                .screenPadding()
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "insights.loading"))
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xxxl)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: AppIconSize.xxxl))
                .foregroundStyle(AppColors.textTertiary)

            Text(String(localized: "insights.emptyState.title"))
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)

            Text(String(localized: "insights.emptyState.description"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xxxl)
        .screenPadding()
    }
}
