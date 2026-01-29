//
//  HistoryFilterSection.swift
//  AIFinanceManager
//
//  Filter section component for HistoryView
//

import SwiftUI

struct HistoryFilterSection: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @Binding var selectedAccountFilter: String?
    @Binding var showingCategoryFilter: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                // Time filter chip
                FilterChip(
                    title: timeFilterManager.currentFilter.displayName,
                    icon: "calendar",
                    onTap: {}
                )
                
                // Account filter menu
                AccountFilterMenu(
                    accounts: accountsViewModel.accounts,
                    selectedAccountId: $selectedAccountFilter
                )
                
                // Category filter button
                CategoryFilterButton(
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
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
    HistoryFilterSection(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        selectedAccountFilter: .constant(nil),
        showingCategoryFilter: .constant(false)
    )
    .environmentObject(TimeFilterManager())
}
