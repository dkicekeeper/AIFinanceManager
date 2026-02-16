//
//  HistoryFilterSection.swift
//  AIFinanceManager
//
//  Filter section component for HistoryView
//  Phase 14: Migrated to UniversalFilterButton
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

    // MARK: - Computed Properties

    private var selectedAccount: Account? {
        accounts.first(where: { $0.id == selectedAccountFilter })
    }

    private var accountFilterTitle: String {
        selectedAccountFilter == nil ? LocalizedRowKey.allAccounts.localized : (selectedAccount?.name ?? LocalizedRowKey.allAccounts.localized)
    }

    private var categoryFilterTitle: String {
        CategoryFilterHelper.displayText(for: selectedCategories)
    }

    var body: some View {
        UniversalCarousel(config: .filter) {
            // Time filter button
            UniversalFilterButton(
                title: timeFilterDisplayName,
                isSelected: false,
                onTap: onTimeFilterTap
            ) {
                Image(systemName: "calendar")
            }

            // Account filter menu
            UniversalFilterButton(
                title: accountFilterTitle,
                isSelected: selectedAccountFilter != nil
            ) {
                if let account = selectedAccount {
                    IconView(source: account.iconSource, size: AppIconSize.sm)
                }
            } menuContent: {
                // "All accounts" option
                Button(action: { selectedAccountFilter = nil }) {
                    HStack {
                        Text(LocalizedRowKey.allAccounts.localized)
                        Spacer()
                        if selectedAccountFilter == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                // Account list
                ForEach(accounts.sortedByOrder()) { account in
                    Button(action: { selectedAccountFilter = account.id }) {
                        HStack(spacing: AppSpacing.sm) {
                            IconView(source: account.iconSource, size: AppIconSize.md)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(AppTypography.bodySmall)
                                let balance = balanceCoordinator.balances[account.id] ?? 0
                                Text(Formatting.formatCurrencySmart(balance, currency: account.currency))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedAccountFilter == account.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Category filter button
            UniversalFilterButton(
                title: categoryFilterTitle,
                isSelected: selectedCategories != nil,
                onTap: { showingCategoryFilter = true }
            ) {
                CategoryFilterHelper.iconView(
                    for: selectedCategories,
                    customCategories: customCategories,
                    incomeCategories: incomeCategories
                )
            }
        }
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
