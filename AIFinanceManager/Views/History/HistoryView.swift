//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Optimized on 2026-01-27 (Phase 2: Decomposition)
//

import SwiftUI

struct HistoryView: View {
    // MARK: - Dependencies

    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - Managers

    @State private var filterCoordinator = HistoryFilterCoordinator()
    @State private var paginationManager = TransactionPaginationManager()
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
        initialCategory: String? = nil,
        initialAccountId: String? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }

    // MARK: - Body

    var body: some View {
        HistoryTransactionsList(
            paginationManager: paginationManager,
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
            updateTransactions()
        }
        .onChange(of: filterCoordinator.selectedAccountFilter) { _, newValue in
            filterCoordinator.applyAccountFilter(newValue)
            updateTransactions()
        }
        .onChange(of: filterCoordinator.searchText) { _, newValue in
            filterCoordinator.applySearch(newValue)
        }
        .onChange(of: filterCoordinator.debouncedSearchText) { _, _ in
            updateTransactions()
        }
        .onChange(of: transactionsViewModel.accounts) { _, _ in
            updateTransactions()
        }
        .onChange(of: transactionsViewModel.selectedCategories) { _, _ in
            filterCoordinator.applyCategoryFilterChange()
            updateTransactions()
        }
        .onChange(of: transactionsViewModel.allTransactions) { _, _ in
            expensesCache.invalidate()
            // Debounce update to avoid excessive recalculations during rapid changes
            // (e.g., when deleting/updating multiple transactions)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                updateTransactions()
            }
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
        }
        .sheet(isPresented: $showingTimeFilter) {
            TimeFilterView(filterManager: timeFilterManager)
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
        // OLD profiler
        PerformanceProfiler.start("HistoryView.onAppear")

        // NEW detailed profiler
        PerformanceLogger.HistoryMetrics.logOnAppear(
            transactionCount: transactionsViewModel.allTransactions.count
        )

        // Set initial account filter
        filterCoordinator.setInitialAccountFilter(initialAccountId)

        // Sync debounced search with current search
        filterCoordinator.debouncedSearchText = filterCoordinator.searchText

        // Load transactions
        updateTransactions()

        PerformanceProfiler.end("HistoryView.onAppear")
        PerformanceLogger.shared.end("HistoryView.onAppear")
    }

    private func updateTransactions() {
        // OLD profiler
        PerformanceProfiler.start("HistoryView.updateTransactions")

        // NEW detailed profiler
        let hasFilters = filterCoordinator.selectedAccountFilter != nil ||
                        !filterCoordinator.debouncedSearchText.isEmpty ||
                        transactionsViewModel.selectedCategories != nil
        PerformanceLogger.HistoryMetrics.logUpdateTransactions(
            transactionCount: transactionsViewModel.allTransactions.count,
            hasFilters: hasFilters
        )

        // Filter transactions
        PerformanceLogger.HistoryMetrics.logFilterTransactions(
            inputCount: transactionsViewModel.allTransactions.count,
            outputCount: 0, // will be updated after filtering
            accountFilter: filterCoordinator.selectedAccountFilter != nil,
            searchText: filterCoordinator.debouncedSearchText
        )

        let filtered = transactionsViewModel.filterTransactionsForHistory(
            timeFilterManager: timeFilterManager,
            accountId: filterCoordinator.selectedAccountFilter,
            searchText: filterCoordinator.debouncedSearchText
        )

        PerformanceLogger.shared.end("TransactionFilter.filterForHistory", additionalMetadata: [
            "outputCount": filtered.count
        ])

        // Group and sort
        PerformanceLogger.HistoryMetrics.logGroupTransactions(
            transactionCount: filtered.count,
            sectionCount: 0 // will be updated after grouping
        )

        let result = transactionsViewModel.groupAndSortTransactionsByDate(filtered)

        PerformanceLogger.shared.end("TransactionGrouping.groupByDate", additionalMetadata: [
            "sectionCount": result.sortedKeys.count
        ])

        // Initialize pagination with new data (single source of truth)
        PerformanceLogger.HistoryMetrics.logPagination(
            totalSections: result.sortedKeys.count,
            visibleSections: min(10, result.sortedKeys.count)
        )

        paginationManager.initialize(grouped: result.grouped, sortedKeys: result.sortedKeys)

        PerformanceLogger.shared.end("Pagination.initialize")

        PerformanceProfiler.end("HistoryView.updateTransactions")
        PerformanceLogger.shared.end("HistoryView.updateTransactions")
    }

    private func resetFilters() {
        filterCoordinator.reset()
        transactionsViewModel.selectedCategories = nil
    }
}

// MARK: - Previews

#Preview("History View") {
    let coordinator = AppCoordinator()
    NavigationStack {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
        .environment(TimeFilterManager())
    }
}
