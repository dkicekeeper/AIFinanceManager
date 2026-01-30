//
//  HistoryTransactionsList.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: HistoryView Decomposition
//
//  Separate view component for displaying paginated transaction list.
//  Extracted to improve modularity and testability.
//

import SwiftUI

/// Displays paginated list of transactions with sections and auto-scroll
struct HistoryTransactionsList: View {

    // MARK: - Dependencies

    @ObservedObject var paginationManager: TransactionPaginationManager
    @ObservedObject var expensesCache: DateSectionExpensesCache
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    // MARK: - Filter State

    let debouncedSearchText: String
    let selectedAccountFilter: String?

    // MARK: - Localized Keys

    let todayKey: String
    let yesterdayKey: String

    // MARK: - Computed Properties

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    // MARK: - Body

    var body: some View {
        let grouped = paginationManager.groupedTransactions
        let sortedKeys = paginationManager.visibleSections

        if grouped.isEmpty && !paginationManager.isLoadingMore {
            emptyStateView
        } else {
            transactionsListView(grouped: grouped, sortedKeys: sortedKeys)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        let emptyMessage: String = {
            if !debouncedSearchText.isEmpty {
                return String(localized: "emptyState.tryDifferentSearch")
            } else if selectedAccountFilter != nil || transactionsViewModel.selectedCategories != nil {
                return String(localized: "emptyState.tryDifferentFilters")
            } else {
                return String(localized: "emptyState.startTracking")
            }
        }()

        return EmptyStateView(
            icon: !debouncedSearchText.isEmpty ? "magnifyingglass" : "doc.text",
            title: !debouncedSearchText.isEmpty
                ? String(localized: "emptyState.searchNoResults")
                : String(localized: "emptyState.noTransactions"),
            description: emptyMessage
        )
        .padding(.top, AppSpacing.xxxl)
    }

    // MARK: - Transactions List

    private func transactionsListView(
        grouped: [String: [Transaction]],
        sortedKeys: [String]
    ) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sortedKeys, id: \.self) { dateKey in
                    Section(
                        header: dateHeader(for: dateKey, transactions: grouped[dateKey] ?? [])
                    ) {
                        ForEach(grouped[dateKey] ?? []) { transaction in
                            TransactionCard(
                                transaction: transaction,
                                currency: baseCurrency,
                                customCategories: categoriesViewModel.customCategories,
                                accounts: accountsViewModel.accounts,
                                viewModel: transactionsViewModel,
                                categoriesViewModel: categoriesViewModel
                            )
                            .listRowInsets(EdgeInsets(
                                top: AppSpacing.sm,
                                leading: AppSpacing.lg,
                                bottom: AppSpacing.sm,
                                trailing: AppSpacing.lg
                            ))
                        }
                    }
                    .id(dateKey)
                    .onAppear {
                        // Trigger pagination when reaching near the end
                        if paginationManager.shouldLoadMore(for: dateKey) {
                            paginationManager.loadNextPage()
                        }
                    }
                }

                // Loading indicator at the bottom
                if paginationManager.isLoadingMore {
                    loadingSection
                }
            }
            .listStyle(PlainListStyle())
            .task {
                await performAutoScroll(proxy: proxy)
            }
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                    .padding()
                Spacer()
            }
        }
    }

    // MARK: - Date Header

    private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
        // Use memoized expenses cache for optimal performance
        let dayExpenses = expensesCache.getExpenses(
            for: dateKey,
            transactions: transactions,
            baseCurrency: baseCurrency,
            viewModel: transactionsViewModel
        )

        return DateSectionHeader(
            dateKey: dateKey,
            dayExpenses: dayExpenses,
            currency: baseCurrency
        )
    }

    // MARK: - Auto Scroll

    private func performAutoScroll(proxy: ScrollViewProxy) async {
        // Calculate delay based on section count
        let delay = HistoryScrollBehavior.calculateScrollDelay(
            sectionCount: paginationManager.visibleSections.count
        )

        try? await Task.sleep(nanoseconds: delay)

        // Find scroll target using behavior logic
        let scrollTarget = HistoryScrollBehavior.findScrollTarget(
            sections: paginationManager.visibleSections,
            grouped: paginationManager.groupedTransactions,
            todayKey: todayKey,
            yesterdayKey: yesterdayKey,
            dateFormatter: DateFormatters.dateFormatter
        )

        // Scroll to target with animation
        if let target = scrollTarget {
            withAnimation {
                proxy.scrollTo(target, anchor: .top)
            }

            #if DEBUG
            print(HistoryScrollBehavior.debugScrollTarget(
                sections: paginationManager.visibleSections,
                grouped: paginationManager.groupedTransactions,
                target: target,
                todayKey: todayKey,
                yesterdayKey: yesterdayKey
            ))
            #endif
        }
    }
}

// MARK: - Preview

#Preview("Transactions List") {
    let coordinator = AppCoordinator()

    HistoryTransactionsList(
        paginationManager: TransactionPaginationManager(),
        expensesCache: DateSectionExpensesCache(),
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        debouncedSearchText: "",
        selectedAccountFilter: nil,
        todayKey: String(localized: "date.today"),
        yesterdayKey: String(localized: "date.yesterday")
    )
}
