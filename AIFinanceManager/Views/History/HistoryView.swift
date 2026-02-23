//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Optimized on 2026-01-27 (Phase 2: Decomposition)
//  Task 10 (2026-02-23): Wired to TransactionPaginationController (FRC-based)
//

import SwiftUI

struct HistoryView: View {
    // MARK: - Dependencies

    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    /// FRC-based pagination controller (read-only, set from AppCoordinator).
    let paginationController: TransactionPaginationController
    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - Managers

    @State private var filterCoordinator = HistoryFilterCoordinator()
    @State private var expensesCache = DateSectionExpensesCache()

    // MARK: - State

    @State private var showingTimeFilter = false

    // MARK: - Initial Filters

    let initialCategory: String?
    let initialAccountId: String?

    // MARK: - Localized Keys

    private var todayKey: String {
        String(localized: "date.today")
    }

    private var yesterdayKey: String {
        String(localized: "date.yesterday")
    }

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        paginationController: TransactionPaginationController,
        initialCategory: String? = nil,
        initialAccountId: String? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.paginationController = paginationController
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }

    // MARK: - Body

    var body: some View {
        HistoryTransactionsList(
            paginationController: paginationController,
            expensesCache: expensesCache,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            debouncedSearchText: filterCoordinator.debouncedSearchText,
            selectedAccountFilter: filterCoordinator.selectedAccountFilter,
            todayKey: todayKey,
            yesterdayKey: yesterdayKey
        )
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                HistoryFilterSection(
                    timeFilterDisplayName: timeFilterManager.currentFilter.displayName,
                    accounts: accountsViewModel.accounts,
                    selectedCategories: transactionsViewModel.selectedCategories,
                    customCategories: categoriesViewModel.customCategories,
                    incomeCategories: transactionsViewModel.incomeCategories,
                    selectedAccountFilter: $filterCoordinator.selectedAccountFilter,
                    showingCategoryFilter: $filterCoordinator.showingCategoryFilter,
                    onTimeFilterTap: { showingTimeFilter = true },
                    balanceCoordinator: accountsViewModel.balanceCoordinator!
                )
            }
            .background(Color(.clear))
        }
        .navigationTitle(String(localized: "navigation.history"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(.clear), for: .navigationBar)
        .searchable(
            text: $filterCoordinator.searchText,
            isPresented: $filterCoordinator.isSearchActive,
            prompt: String(localized: "search.placeholder")
        )
        .task {
            setupInitialFilters()
        }
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            HapticManager.selection()
            applyFiltersToController()
        }
        .onChange(of: filterCoordinator.selectedAccountFilter) { _, newValue in
            filterCoordinator.applyAccountFilter(newValue)
            applyFiltersToController()
        }
        .onChange(of: filterCoordinator.searchText) { _, newValue in
            filterCoordinator.applySearch(newValue)
        }
        .onChange(of: filterCoordinator.debouncedSearchText) { _, _ in
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.accounts) { _, _ in
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.selectedCategories) { _, _ in
            filterCoordinator.applyCategoryFilterChange()
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.allTransactions) { _, _ in
            expensesCache.invalidate()
        }
        .onChange(of: transactionsViewModel.appSettings.baseCurrency) { _, _ in
            expensesCache.invalidate()
        }
        .onDisappear {
            resetFilters()
        }
        .sheet(isPresented: $filterCoordinator.showingCategoryFilter) {
            CategoryFilterView(
                expenseCategories: transactionsViewModel.expenseCategories,
                incomeCategories: transactionsViewModel.incomeCategories,
                currentFilter: transactionsViewModel.selectedCategories,
                onFilterChanged: { newFilter in
                    transactionsViewModel.selectedCategories = newFilter
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTimeFilter) {
            TimeFilterView(filterManager: timeFilterManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Private Methods

    private func setupInitialFilters() {
        if let category = initialCategory {
            transactionsViewModel.selectedCategories = [category]
        } else {
            transactionsViewModel.selectedCategories = nil
        }
    }

    private func handleOnAppear() {
        PerformanceProfiler.start("HistoryView.onAppear")
        PerformanceLogger.HistoryMetrics.logOnAppear(
            transactionCount: transactionsViewModel.allTransactions.count
        )

        // Set initial account filter
        filterCoordinator.setInitialAccountFilter(initialAccountId)

        // Sync debounced search with current search
        filterCoordinator.debouncedSearchText = filterCoordinator.searchText

        // Apply current filters to the FRC controller
        applyFiltersToController()

        PerformanceProfiler.end("HistoryView.onAppear")
        PerformanceLogger.shared.end("HistoryView.onAppear")
    }

    /// Forwards current filter state to the FRC-based pagination controller.
    /// The FRC handles predicate updates and triggers `controllerDidChangeContent`
    /// which rebuilds `sections` — no manual grouping/sorting needed.
    private func applyFiltersToController() {
        PerformanceProfiler.start("HistoryView.applyFiltersToController")

        let hasFilters = filterCoordinator.selectedAccountFilter != nil ||
                        !filterCoordinator.debouncedSearchText.isEmpty ||
                        transactionsViewModel.selectedCategories != nil
        PerformanceLogger.HistoryMetrics.logUpdateTransactions(
            transactionCount: transactionsViewModel.allTransactions.count,
            hasFilters: hasFilters
        )

        // Forward search query
        paginationController.searchQuery = filterCoordinator.debouncedSearchText

        // Forward account filter
        paginationController.selectedAccountId = filterCoordinator.selectedAccountFilter

        // Forward category filter (first element from the set, matching FRC predicate)
        paginationController.selectedCategoryId = transactionsViewModel.selectedCategories?.first

        // Forward time filter as a date range
        let timeFilter = timeFilterManager.currentFilter
        let range = timeFilter.dateRange()
        // allTime maps to a sentinel range; avoid sending the 100-year sentinel range
        // because it is functionally equivalent to no predicate (nil).
        if timeFilter.preset == .allTime {
            paginationController.dateRange = nil
        } else {
            paginationController.dateRange = (start: range.start, end: range.end)
        }

        PerformanceProfiler.end("HistoryView.applyFiltersToController")
        PerformanceLogger.shared.end("HistoryView.updateTransactions")
    }

    private func resetFilters() {
        filterCoordinator.reset()
        transactionsViewModel.selectedCategories = nil
        // Clear all FRC filters so the controller is clean for next appearance
        paginationController.searchQuery = ""
        paginationController.selectedAccountId = nil
        paginationController.selectedCategoryId = nil
        paginationController.dateRange = nil
    }
}

// MARK: - Previews

#Preview("History View") {
    let coordinator = AppCoordinator()
    NavigationStack {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            paginationController: coordinator.transactionPaginationController
        )
        .environment(TimeFilterManager())
    }
}
