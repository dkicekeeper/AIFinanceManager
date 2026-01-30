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

    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager

    // MARK: - Managers

    @StateObject private var filterCoordinator = HistoryFilterCoordinator()
    @StateObject private var paginationManager = TransactionPaginationManager()
    @StateObject private var expensesCache = DateSectionExpensesCache()

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
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    selectedAccountFilter: $filterCoordinator.selectedAccountFilter,
                    showingCategoryFilter: $filterCoordinator.showingCategoryFilter
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
            updateTransactions()
        }
        .onChange(of: transactionsViewModel.appSettings.baseCurrency) { _, _ in
            expensesCache.invalidate()
        }
        .onDisappear {
            resetFilters()
        }
        .sheet(isPresented: $filterCoordinator.showingCategoryFilter) {
            CategoryFilterView(viewModel: transactionsViewModel)
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

        // Set initial account filter
        filterCoordinator.setInitialAccountFilter(initialAccountId)

        // Sync debounced search with current search
        filterCoordinator.debouncedSearchText = filterCoordinator.searchText

        // Load transactions
        updateTransactions()

        PerformanceProfiler.end("HistoryView.onAppear")
    }

    private func updateTransactions() {
        PerformanceProfiler.start("HistoryView.updateTransactions")

        // Filter transactions
        let filtered = transactionsViewModel.filterTransactionsForHistory(
            timeFilterManager: timeFilterManager,
            accountId: filterCoordinator.selectedAccountFilter,
            searchText: filterCoordinator.debouncedSearchText
        )

        // Group and sort
        let result = transactionsViewModel.groupAndSortTransactionsByDate(filtered)

        // Initialize pagination with new data (single source of truth)
        paginationManager.initialize(grouped: result.grouped, sortedKeys: result.sortedKeys)

        PerformanceProfiler.end("HistoryView.updateTransactions")
    }

    private func resetFilters() {
        filterCoordinator.reset()
        transactionsViewModel.selectedCategories = nil
    }
}

// MARK: - Previews

#Preview("History View") {
    let coordinator = AppCoordinator()
    NavigationView {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
        .environmentObject(TimeFilterManager())
    }
}
