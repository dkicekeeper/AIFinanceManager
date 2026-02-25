//
//  AccountsManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import OSLog
import SwiftUI

struct AccountsManagementView: View {
    let accountsViewModel: AccountsViewModel
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    @Environment(TransactionStore.self) private var transactionStore // Phase 7.5: TransactionStore integration
    @Environment(\.dismiss) var dismiss
    @State private var showingAddAccount = false
    @State private var showingAddDeposit = false
    @State private var editingAccount: Account?
    @State private var accountToDelete: Account?
    @State private var showingAccountDeleteDialog = false
    @State private var isReordering = false

    // Кешируем baseCurrency для оптимизации
    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    private let logger = Logger(subsystem: "AIFinanceManager", category: "AccountsManagementView")

    // Filtered and sorted accounts
    private var sortedAccounts: [Account] {
        accountsViewModel.accounts.sortedByOrder()
    }

    // MARK: - Methods

    private func moveAccount(from source: IndexSet, to destination: Int) {
        var updatedAccounts = sortedAccounts
        updatedAccounts.move(fromOffsets: source, toOffset: destination)

        // Update order for all accounts
        for (index, account) in updatedAccounts.enumerated() {
            var updatedAccount = account
            updatedAccount.order = index
            accountsViewModel.updateAccount(updatedAccount)
        }

        // Invalidate caches to ensure the new order is reflected everywhere
        transactionsViewModel.invalidateCaches()

        HapticManager.selection()
    }
    
    var body: some View {
        Group {
            if accountsViewModel.accounts.isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: String(localized: "emptyState.noAccounts"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "account.newAccount"),
                    action: {
                        showingAddAccount = true
                    }
                )
            } else if let coordinator = accountsViewModel.balanceCoordinator {
                List {
                    ForEach(sortedAccounts) { account in
                        AccountRow(
                            account: account,
                            onEdit: { editingAccount = account },
                            onDelete: {
                                HapticManager.warning()
                                accountToDelete = account
                                showingAccountDeleteDialog = true
                            },
                            balanceCoordinator: coordinator,
                            interestToday: account.depositInfo.flatMap {
                                let val = DepositInterestService.calculateInterestToToday(depositInfo: $0)
                                return val > 0 ? NSDecimalNumber(decimal: val).doubleValue : nil
                            },
                            nextPostingDate: account.depositInfo.flatMap {
                                DepositInterestService.nextPostingDate(depositInfo: $0)
                            }
                        )
                    }
                    .onMove(perform: isReordering ? moveAccount : nil)
                }
                .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
            }
        }
        .navigationTitle(String(localized: "settings.accounts"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Phase 7.5: Пересчитываем проценты депозитов с TransactionStore
            depositsViewModel.reconcileAllDeposits(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    Task {
                        do {
                            _ = try await transactionStore.add(transaction)
                        } catch {
                            logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
                        }
                    }
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppSpacing.md) {
                    Button {
                        HapticManager.light()
                        withAnimation {
                            isReordering.toggle()
                        }
                    } label: {
                        Image(systemName: isReordering ? "checkmark" : "arrow.up.arrow.down")
                            .foregroundStyle(isReordering ? .blue : .primary)
                    }

                    Menu {
                        Button(action: {
                            HapticManager.light()
                            showingAddAccount = true
                        }) {
                            Label(String(localized: "account.newAccount"), systemImage: "creditcard")
                        }
                        Button(action: {
                            HapticManager.light()
                            showingAddDeposit = true
                        }) {
                            Label(String(localized: "account.newDeposit"), systemImage: "banknote")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountEditView(
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: nil,
                onSave: { account in
                    HapticManager.success()
                    Task {
                        await accountsViewModel.addAccount(name: account.name, initialBalance: account.initialBalance ?? 0, currency: account.currency, iconSource: account.iconSource)
                        transactionsViewModel.syncAccountsFrom(accountsViewModel)
                        showingAddAccount = false
                    }
                },
                onCancel: { showingAddAccount = false }
            )
        }
        .sheet(isPresented: $showingAddDeposit) {
            DepositEditView(
                depositsViewModel: depositsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: nil,
                onSave: { account in
                    if let depositInfo = account.depositInfo {
                        HapticManager.success()
                        depositsViewModel.addDeposit(
                            name: account.name,
                            currency: account.currency,
                            bankName: depositInfo.bankName,
                            iconSource: account.iconSource,
                            principalBalance: depositInfo.principalBalance,
                            interestRateAnnual: depositInfo.interestRateAnnual,
                            interestPostingDay: depositInfo.interestPostingDay,
                            capitalizationEnabled: depositInfo.capitalizationEnabled
                        )
                        // Phase 7.5: Reconcile deposits after adding with TransactionStore
                        depositsViewModel.reconcileAllDeposits(
                            allTransactions: transactionsViewModel.allTransactions,
                            onTransactionCreated: { transaction in
                                Task {
                                    do {
                                        _ = try await transactionStore.add(transaction)
                                    } catch {
                                        logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
                                    }
                                }
                            }
                        )
                    }
                    showingAddDeposit = false
                },
                onCancel: { showingAddDeposit = false }
            )
        }
        .sheet(item: $editingAccount) { account in
            Group {
                if account.isDeposit {
                    DepositEditView(
                        depositsViewModel: depositsViewModel,
                        transactionsViewModel: transactionsViewModel,
                        account: account,
                        onSave: { updatedAccount in
                            HapticManager.success()
                            depositsViewModel.updateDeposit(updatedAccount)
                            transactionsViewModel.recalculateAccountBalances()
                            editingAccount = nil
                        },
                        onCancel: { editingAccount = nil }
                    )
                } else {
                    AccountEditView(
                        accountsViewModel: accountsViewModel,
                        transactionsViewModel: transactionsViewModel,
                        account: account,
                        onSave: { updatedAccount in
                            HapticManager.success()
                            accountsViewModel.updateAccount(updatedAccount)
                            transactionsViewModel.syncAccountsFrom(accountsViewModel)
                            editingAccount = nil
                        },
                        onCancel: { editingAccount = nil }
                    )
                }
            }
        }
        .alert(String(localized: "account.deleteTitle"), isPresented: $showingAccountDeleteDialog, presenting: accountToDelete) { account in
            Button(String(localized: "button.cancel"), role: .cancel) {
                accountToDelete = nil
            }
            Button(String(localized: "account.deleteOnlyAccount"), role: .destructive) {
                HapticManager.warning()

                accountsViewModel.deleteAccount(account, deleteTransactions: false)

                // Очистить состояние удаленного счета ПЕРЕД пересчетом
                transactionsViewModel.cleanupDeletedAccount(account.id)

                // Транзакции остаются, accountName сохранен
                // NOTE: Aggregate cache is NOT touched - transactions unchanged, aggregates remain valid
                transactionsViewModel.syncAccountsFrom(accountsViewModel)

                accountToDelete = nil
            }
            Button(String(localized: "account.deleteAccountAndTransactions"), role: .destructive) {
                HapticManager.warning()

                accountsViewModel.deleteAccount(account, deleteTransactions: true)

                // Удаляем все связанные транзакции
                transactionsViewModel.allTransactions.removeAll {
                    $0.accountId == account.id || $0.targetAccountId == account.id
                }

                // Очистить состояние удаленного счета ПЕРЕД пересчетом
                transactionsViewModel.cleanupDeletedAccount(account.id)

                // CRITICAL: Use new method to clear and rebuild aggregate cache
                transactionsViewModel.clearAndRebuildAggregateCache()

                // syncAccountsFrom уже вызывает recalculateAccountBalances, не дублируем
                transactionsViewModel.syncAccountsFrom(accountsViewModel)

                accountToDelete = nil
            }
        } message: { account in
            Text(String(format: String(localized: "account.deleteMessage"), account.name))
        }
    }
}

#Preview("Accounts Management") {
    let coordinator = AppCoordinator()
    NavigationStack {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Accounts Management - Empty") {
    let coordinator = AppCoordinator()
    // Phase 16: accounts is computed from TransactionStore — empty by default
    return NavigationStack {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Account Row") {
    // Sample accounts with different characteristics
    let sampleAccounts = [
        Account(
            id: "preview-1",
            name: "Kaspi Gold",
            currency: "KZT",
            iconSource: .bankLogo(.kaspi),
            initialBalance: 500000
        ),
        Account(
            id: "preview-2",
            name: "Main Savings",
            currency: "USD",
            iconSource: .bankLogo(.halykBank),
            initialBalance: 15000
        ),
        Account(
            id: "preview-3",
            name: "Halyk Deposit",
            currency: "KZT",
            iconSource: .bankLogo(.halykBank),
            depositInfo: DepositInfo(
                bankName: "Halyk Bank",
                principalBalance: Decimal(1000000),
                capitalizationEnabled: true,
                interestRateAnnual: Decimal(12.5),
                interestPostingDay: 15
            ),
            initialBalance: 1000000
        ),
        Account(
            id: "preview-4",
            name: "EUR Account",
            currency: "EUR",
            iconSource: .bankLogo(.alatauCityBank),
            initialBalance: 2500
        ),
        Account(
            id: "preview-5",
            name: "Jusan Deposit",
            currency: "KZT",
            iconSource: .bankLogo(.jusan),
            depositInfo: DepositInfo(
                bankName: "Jusan Bank",
                principalBalance: Decimal(2000000),
                capitalizationEnabled: false,
                interestRateAnnual: Decimal(10.0),
                interestPostingDay: 1
            ),
            initialBalance: 2000000
        )
    ]
    
    let coordinator = AppCoordinator()

    if let balanceCoordinator = coordinator.accountsViewModel.balanceCoordinator {
        List {
            ForEach(sampleAccounts) { account in
                AccountRow(
                    account: account,
                    onEdit: {},
                    onDelete: {},
                    balanceCoordinator: balanceCoordinator
                )
            }
        }
        .listStyle(PlainListStyle())
    }
}

