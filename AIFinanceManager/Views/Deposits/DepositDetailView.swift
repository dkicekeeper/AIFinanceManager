//
//  DepositDetailView.swift
//  AIFinanceManager
//
//  Detail view for deposit accounts
//

import SwiftUI

struct DepositDetailView: View {
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    let balanceCoordinator: BalanceCoordinator
    @Environment(TransactionStore.self) private var transactionStore // Phase 7.5: TransactionStore integration
    let accountId: String
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var showingEditView = false
    @State private var showingTransferTo = false // Пополнение депозита
    @State private var showingTransferFrom = false // Перевод с депозита на счет
    @State private var showingRateChange = false
    @State private var showingDeleteConfirmation = false
    @State private var showingHistory = false
    @Environment(\.dismiss) var dismiss
    
    private var account: Account? {
        depositsViewModel.getDeposit(by: accountId)
    }
    
    private var depositInfo: DepositInfo? {
        account?.depositInfo
    }
    
    var body: some View {
        Group {
            if let account = account {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Info card
                        if let depositInfo = depositInfo {
                            depositInfoCard(depositInfo: depositInfo, account: account)
                                .screenPadding()
                            
                            // Actions
                            actionsSection
                                .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .navigationTitle(account.name)
            } else {
                EmptyStateView(
                    icon: "banknote",
                    title: String(localized: "deposit.notFound"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
                .navigationTitle(String(localized: "deposit.title"))
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.selection()
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        HapticManager.selection()
                        showingEditView = true
                    } label: {
                        Label(String(localized: "deposit.edit"), systemImage: "pencil")
                    }
                    
                    Button {
                        HapticManager.selection()
                        showingRateChange = true
                    } label: {
                        Label(String(localized: "deposit.changeRate"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        HapticManager.warning()
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "deposit.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingHistory) {
            if let account = account {
                NavigationStack {
                    // Note: Need to pass CategoriesViewModel from coordinator
                    // For now using transactionsViewModel directly
                    HistoryView(
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: depositsViewModel.accountsViewModel,
                        categoriesViewModel: CategoriesViewModel(repository: depositsViewModel.repository),
                        initialAccountId: account.id
                    )
                        .environment(timeFilterManager)
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            if let account = account {
                DepositEditView(
                    depositsViewModel: depositsViewModel,
                    transactionsViewModel: transactionsViewModel,
                    account: account,
                    onSave: { updatedAccount in
                        HapticManager.success()
                        depositsViewModel.updateDeposit(updatedAccount)
                        transactionsViewModel.recalculateAccountBalances()
                        showingEditView = false
                    },
                    onCancel: {
                        showingEditView = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingTransferTo) {
            if let account = account {
                AccountActionView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel,
                    account: account,
                    transferDirection: .toDeposit
                )
                    .environment(timeFilterManager)
            }
        }
        .sheet(isPresented: $showingTransferFrom) {
            if let account = account {
                AccountActionView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel,
                    account: account,
                    transferDirection: .fromDeposit
                )
                    .environment(timeFilterManager)
            }
        }
        .sheet(isPresented: $showingRateChange) {
            if let account = account {
                DepositRateChangeView(
                    account: account,
                    onRateChanged: { effectiveFrom, annualRate, note in
                        depositsViewModel.addDepositRateChange(
                            accountId: account.id,
                            effectiveFrom: effectiveFrom,
                            annualRate: annualRate,
                            note: note
                        )
                    },
                    onComplete: {
                        HapticManager.success()
                        showingRateChange = false
                    }
                )
            }
        }
        .alert(String(localized: "deposit.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "button.delete"), role: .destructive) {
                if let account = account {
                    HapticManager.warning()
                    depositsViewModel.deleteDeposit(account)
                    // Also delete related transactions
                    transactionsViewModel.allTransactions.removeAll { 
                        $0.accountId == account.id || $0.targetAccountId == account.id 
                    }
                    transactionsViewModel.recalculateAccountBalances()
                }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "deposit.deleteMessage"))
        }
        .task {
            // Phase 7.5: Пересчитываем проценты при открытии с TransactionStore
            depositsViewModel.reconcileAllDeposits(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    Task {
                        do {
                            try await transactionStore.add(transaction)
                        } catch {
                            print("❌ Failed to create interest transaction: \(error.localizedDescription)")
                        }
                    }
                }
            )
        }
    }
    
    private func depositInfoCard(depositInfo: DepositInfo, account: Account) -> some View {
        // Кешируем вычисления для оптимизации
        let interestToToday = DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
        let nextPosting = DepositInterestService.nextPostingDate(depositInfo: depositInfo)
        
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack {
                account.bankLogo.image(size: AppIconSize.xxl)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h3)
                    Text(depositInfo.bankName)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            // Balance
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "deposit.balance"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                let balance = balanceCoordinator.balances[account.id] ?? 0
                FormattedAmountText(
                    amount: balance,
                    currency: account.currency,
                    fontSize: AppTypography.h2
                )
            }

            // Interest info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "deposit.interestToday"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: interestToToday).doubleValue,
                    currency: account.currency,
                    fontSize: AppTypography.h4,
                    color: .blue
                )
            }
            
            Divider()
            
            // Details
            InfoRow(
                label: String(localized: "deposit.rate"),
                value: String(format: String(localized: "deposit.rateAnnual"), formatRate(depositInfo.interestRateAnnual))
            )
            InfoRow(
                label: String(localized: "deposit.capitalization"),
                value: depositInfo.capitalizationEnabled ? String(localized: "deposit.capitalizationEnabled") : String(localized: "deposit.capitalizationDisabled")
            )
            InfoRow(
                label: String(localized: "deposit.postingDay"),
                value: "\(depositInfo.interestPostingDay)"
            )
            
            if let nextPosting = nextPosting {
                InfoRow(
                    label: String(localized: "deposit.nextPosting"),
                    value: formatDate(nextPosting)
                )
            }
        }
        .glassCardStyle()
    }
    
    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                HapticManager.light()
                showingTransferTo = true
            } label: {
                Label(String(localized: "deposit.topUp"), systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()
            
            Button {
                HapticManager.light()
                showingTransferFrom = true
            } label: {
                Label(String(localized: "deposit.transferToAccount"), systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func formatRate(_ rate: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: rate).doubleValue)
    }
    
    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }
}


// MARK: - Previews

#Preview("Deposit Detail View") {
    let coordinator = AppCoordinator()

    NavigationStack {
        DepositDetailView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!,
            accountId: coordinator.depositsViewModel.deposits.first?.id ?? "test"
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Deposit Detail View - Not Found") {
    let coordinator = AppCoordinator()

    NavigationStack {
        DepositDetailView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!,
            accountId: "non-existent"
        )
        .environment(TimeFilterManager())
    }
}
