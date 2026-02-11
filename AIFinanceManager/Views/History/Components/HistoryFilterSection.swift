//
//  HistoryFilterSection.swift
//  AIFinanceManager
//
//  Filter section component for HistoryView
//

import SwiftUI

struct HistoryFilterSection: View {
    let timeFilterDisplayName: String
    let accounts: [Account]
    let selectedCategories: Set<String>?
    let customCategories: [CustomCategory]
    let incomeCategories: [String]
    @Binding var selectedAccountFilter: String?
    @Binding var showingCategoryFilter: Bool
    let onTimeFilterTap: () -> Void
    let balanceCoordinator: BalanceCoordinator

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                // Time filter chip
                FilterChip(
                    title: timeFilterDisplayName,
                    icon: "calendar",
                    onTap: onTimeFilterTap
                )

                // Account filter menu
                AccountFilterMenu(
                    accounts: accounts,
                    selectedAccountId: $selectedAccountFilter,
                    balanceCoordinator: balanceCoordinator
                )

                // Category filter button
                CategoryFilterButton(
                    selectedCategories: selectedCategories,
                    customCategories: customCategories,
                    incomeCategories: incomeCategories,
                    onTap: { showingCategoryFilter = true }
                )
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview {
    let coordinator = AppCoordinator()

    return HistoryFilterSection(
        timeFilterDisplayName: "Этот месяц",
        accounts: [],
        selectedCategories: nil,
        customCategories: [],
        incomeCategories: ["Salary"],
        selectedAccountFilter: .constant(nil),
        showingCategoryFilter: .constant(false),
        onTimeFilterTap: {},
        balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
    )
}
