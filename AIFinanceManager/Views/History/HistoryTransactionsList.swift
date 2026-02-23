//
//  HistoryTransactionsList.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: HistoryView Decomposition
//  Task 10 (2026-02-23): Renders from TransactionPaginationController (FRC-based sections)
//
//  Renders a paginated, date-sectioned transaction list.
//  Data source: TransactionPaginationController (NSFetchedResultsController)
//  — only the currently visible batch of 50 rows is held in memory.
//

import SwiftUI

/// Displays FRC-backed list of transactions with date sections.
/// Section keys from the FRC are "YYYY-MM-DD"; `displayDateKey(_:)` converts
/// them to human-readable strings ("Today", "Yesterday", "15 Feb", etc.).
struct HistoryTransactionsList: View {

    // MARK: - Dependencies

    let paginationController: TransactionPaginationController
    let expensesCache: DateSectionExpensesCache
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    // MARK: - Filter State (for empty-state messaging)

    let debouncedSearchText: String
    let selectedAccountFilter: String?

    // MARK: - Localized Keys

    let todayKey: String
    let yesterdayKey: String

    // MARK: - Private Formatters

    /// "YYYY-MM-DD" → Date
    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Date → "15 Feb" (current year omitted)
    private static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    /// Date → "15 Feb 2023" (cross-year)
    private static let longDisplay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f
    }()

    // MARK: - Computed Properties

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    // MARK: - Body

    var body: some View {
        let sections = paginationController.sections

        if sections.isEmpty {
            emptyStateView
        } else {
            transactionsListView(sections: sections)
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

    private func transactionsListView(sections: [TransactionSection]) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sections) { section in
                    let displayKey = displayDateKey(from: section.date)
                    Section(
                        header: dateHeader(
                            dateKey: displayKey,
                            transactions: section.transactions
                        )
                    ) {
                        ForEach(section.transactions) { transaction in
                            TransactionCard(
                                transaction: transaction,
                                currency: baseCurrency,
                                customCategories: categoriesViewModel.customCategories,
                                accounts: accountsViewModel.accounts,
                                viewModel: transactionsViewModel,
                                categoriesViewModel: categoriesViewModel,
                                accountsViewModel: accountsViewModel,
                                balanceCoordinator: accountsViewModel.balanceCoordinator
                            )
                            .listRowInsets(EdgeInsets(
                                top: AppSpacing.sm,
                                leading: AppSpacing.lg,
                                bottom: AppSpacing.sm,
                                trailing: AppSpacing.lg
                            ))
                        }
                    }
                    .id(section.id)
                }
            }
            .listStyle(PlainListStyle())
            .task {
                await performAutoScroll(proxy: proxy, sections: sections)
            }
        }
    }

    // MARK: - Date Header

    private func dateHeader(dateKey: String, transactions: [Transaction]) -> some View {
        let dayExpenses = expensesCache.getExpenses(
            for: dateKey,
            transactions: transactions,
            baseCurrency: baseCurrency,
            viewModel: transactionsViewModel
        )

        return DateSectionHeaderView(
            dateKey: dateKey,
            amount: dayExpenses > 0 ? dayExpenses : nil,
            currency: baseCurrency
        )
    }

    // MARK: - Auto Scroll

    private func performAutoScroll(proxy: ScrollViewProxy, sections: [TransactionSection]) async {
        let delay = HistoryScrollBehavior.calculateScrollDelay(sectionCount: sections.count)
        try? await Task.sleep(nanoseconds: delay)

        // Find the most recent non-future section (sections are sorted newest-first by FRC).
        // The FRC sorts descending by date, so the first section whose date is <= today is
        // the right scroll target — but we also honour today/yesterday priority.
        guard let target = findScrollTarget(in: sections) else { return }

        withAnimation {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    /// Finds the best section id to auto-scroll to.
    /// Priority: today → yesterday → first past section → first section.
    private func findScrollTarget(in sections: [TransactionSection]) -> String? {
        guard !sections.isEmpty else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        for section in sections {
            guard let date = Self.isoParser.date(from: section.date) else { continue }
            let sectionStart = calendar.startOfDay(for: date)

            if sectionStart == todayStart { return section.id }
        }
        for section in sections {
            guard let date = Self.isoParser.date(from: section.date) else { continue }
            let sectionStart = calendar.startOfDay(for: date)
            if sectionStart == yesterdayStart { return section.id }
        }
        for section in sections {
            guard let date = Self.isoParser.date(from: section.date) else { continue }
            let sectionStart = calendar.startOfDay(for: date)
            if sectionStart <= todayStart { return section.id }
        }
        return sections.first?.id
    }

    // MARK: - Date Display Conversion

    /// Converts a "YYYY-MM-DD" FRC section key to a human-readable display string.
    /// Returns "Today", "Yesterday", a short date ("15 Feb"), or a long date ("15 Feb 2023").
    private func displayDateKey(from isoDate: String) -> String {
        guard let date = Self.isoParser.date(from: isoDate) else {
            return isoDate
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sectionDay = calendar.startOfDay(for: date)

        if sectionDay == today {
            return todayKey
        }
        if let diff = calendar.dateComponents([.day], from: sectionDay, to: today).day, diff == 1 {
            return yesterdayKey
        }

        let currentYear = calendar.component(.year, from: Date())
        let sectionYear = calendar.component(.year, from: date)
        if sectionYear == currentYear {
            return Self.shortDisplay.string(from: date)
        }
        return Self.longDisplay.string(from: date)
    }
}

// MARK: - Preview

#Preview("Transactions List") {
    let coordinator = AppCoordinator()

    HistoryTransactionsList(
        paginationController: coordinator.transactionPaginationController,
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
