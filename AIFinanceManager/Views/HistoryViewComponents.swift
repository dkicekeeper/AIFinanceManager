//
//  HistoryViewComponents.swift
//  AIFinanceManager
//
//  Extracted components from HistoryView for better modularity
//

import SwiftUI

// MARK: - History Filter Section

struct HistoryFilterSection: View {
    @ObservedObject var viewModel: TransactionsViewModel
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
                    accounts: viewModel.accounts,
                    selectedAccountId: $selectedAccountFilter
                )
                
                // Category filter button
                CategoryFilterButton(
                    viewModel: viewModel,
                    onTap: { showingCategoryFilter = true }
                )
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Account Filter Menu

struct AccountFilterMenu: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    
    var body: some View {
        Menu {
            Button(action: { selectedAccountId = nil }) {
                HStack {
                    Text("Все счета")
                    Spacer()
                    if selectedAccountId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            ForEach(accounts) { account in
                Button(action: { selectedAccountId = account.id }) {
                    HStack(spacing: AppSpacing.sm) {
                        account.bankLogo.image(size: AppIconSize.md)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(AppTypography.bodySmall)
                            Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedAccountId == account.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let selectedAccount = accounts.first(where: { $0.id == selectedAccountId })
            HStack(spacing: AppSpacing.sm) {
                if let account = selectedAccount {
                    account.bankLogo.image(size: AppIconSize.sm)
                }
                Text(selectedAccountId == nil ? "Все счета" : (selectedAccount?.name ?? "Все счета"))
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(Color(.systemGray5))
            .cornerRadius(AppRadius.pill)
        }
    }
}

// MARK: - Category Filter Button

struct CategoryFilterButton: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let onTap: () -> Void
    
    private var categoryFilterText: String {
        guard let selectedCategories = viewModel.selectedCategories else {
            return "Все категории"
        }
        if selectedCategories.count == 1 {
            return selectedCategories.first ?? "Все категории"
        }
        return "\(selectedCategories.count) категорий"
    }
    
    @ViewBuilder
    private var categoryFilterIcon: some View {
        if let selectedCategories = viewModel.selectedCategories,
           selectedCategories.count == 1,
           let category = selectedCategories.first {
            let isIncome: Bool = {
                if let customCategory = viewModel.customCategories.first(where: { $0.name == category }) {
                    return customCategory.type == .income
                } else {
                    return viewModel.incomeCategories.contains(category)
                }
            }()
            let categoryType: TransactionType = isIncome ? .income : .expense
            let iconName = CategoryIcon.iconName(for: category, type: categoryType, customCategories: viewModel.customCategories)
            let iconColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: viewModel.customCategories)
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(isIncome ? Color.green : iconColor)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                categoryFilterIcon
                Text(categoryFilterText)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(viewModel.selectedCategories != nil ? Color.blue.opacity(0.2) : Color(.systemGray5))
            .cornerRadius(AppRadius.pill)
        }
    }
}

#Preview("History Filter Section") {
    HistoryFilterSection(
        viewModel: TransactionsViewModel(),
        selectedAccountFilter: .constant(nil),
        showingCategoryFilter: .constant(false)
    )
    .environmentObject(TimeFilterManager())
}
