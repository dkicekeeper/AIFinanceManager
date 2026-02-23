//
//  InsightsView.swift
//  AIFinanceManager
//
//  Phase 23: Insights Performance & UI fixes
//  - P7: InsightsSummaryHeader now receives PeriodDataPoint directly (no per-render conversion)
//  - Loading / empty state kept; sections unchanged
//  Phase 27: Granularity picker moved to toolbar (top-left Menu)
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
                if !insightsViewModel.isLoading && !insightsViewModel.hasData {
                    emptyState
                } else {
                    insightsSummaryHeaderSection
                    insightsFilterSection
                    insightsSectionsSection
                }
            }
            .padding(.vertical, AppSpacing.md)
            .animation(.spring(response: 0.4), value: insightsViewModel.isLoading)
        }
        .navigationTitle(String(localized: "insights.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("", selection: $selectedGranularity) {
                        ForEach(InsightGranularity.allCases) { g in
                            Label(g.displayName, systemImage: g.icon)
                                .tag(g)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(selectedGranularity.shortName, systemImage: selectedGranularity.icon)
                }
            }
        }
        .onChange(of: selectedGranularity) { _, new in
            HapticManager.light()
            insightsViewModel.switchGranularity(new)
        }
        .onAppear {
            // Sync picker to ViewModel state — handles the case where the user returns
            // to the tab after the ViewModel already has a different granularity selected.
            selectedGranularity = insightsViewModel.currentGranularity
            insightsViewModel.onAppear()
        }
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

    // MARK: - Per-Section Skeleton Sections

    private var insightsSummaryHeaderSection: some View {
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
                periodDataPoints: insightsViewModel.periodDataPoints,
                healthScore: insightsViewModel.healthScore
            )
            .screenPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .skeletonLoading(isLoading: insightsViewModel.isLoading) {
            InsightsSummaryHeaderSkeleton()
                .padding(.horizontal, AppSpacing.lg)
        }
    }

    private var insightsFilterSection: some View {
        categoryFilterCarousel
            .skeletonLoading(isLoading: insightsViewModel.isLoading) {
                InsightsFilterCarouselSkeleton()
            }
    }

    private var insightsSectionsSection: some View {
        insightSections
            .skeletonLoading(isLoading: insightsViewModel.isLoading) {
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        InsightCardSkeleton()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
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
            InsightsSectionView(
                category: .spending,
                insights: insightsViewModel.spendingInsights,
                currency: insightsViewModel.baseCurrency,
                onCategoryTap: { [insightsViewModel] item in
                    AnyView(
                        CategoryDeepDiveView(
                            categoryName: item.categoryName,
                            color: item.color,
                            iconSource: item.iconSource,
                            currency: insightsViewModel.baseCurrency,
                            viewModel: insightsViewModel
                        )
                    )
                },
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .income,
                insights: insightsViewModel.incomeInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .budget,
                insights: insightsViewModel.budgetInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .recurring,
                insights: insightsViewModel.recurringInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .cashFlow,
                insights: insightsViewModel.cashFlowInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .wealth,
                insights: insightsViewModel.wealthInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .savings,
                insights: insightsViewModel.savingsInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()

            InsightsSectionView(
                category: .forecasting,
                insights: insightsViewModel.forecastingInsights,
                currency: insightsViewModel.baseCurrency,
                granularity: insightsViewModel.currentGranularity
            )
            .screenPadding()
            
        } else {
            // Show filtered insights without section headers
            ForEach(filtered) { insight in
                NavigationLink(destination: InsightDetailView(insight: insight, currency: insightsViewModel.baseCurrency)) {
                    InsightsCardView(insight: insight)
                }
                .buttonStyle(.plain)
            }
            .screenPadding()
        }
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
