//
//  AccountsManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountsManagementView: View {
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var depositsViewModel: DepositsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddAccount = false
    @State private var showingAddDeposit = false
    @State private var editingAccount: Account?
    @State private var accountToDelete: Account?
    @State private var showingAccountDeleteDialog = false

    // Кешируем baseCurrency для оптимизации
    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
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
            } else {
                List {
                    ForEach(accountsViewModel.accounts) { account in
                        AccountRow(
                            account: account,
                            currency: baseCurrency,
                            onEdit: { editingAccount = account },
                            onDelete: {
                                HapticManager.warning()
                                accountToDelete = account
                                showingAccountDeleteDialog = true
                            },
                            balanceCoordinator: accountsViewModel.balanceCoordinator!,
                            interestToday: account.depositInfo.flatMap {
                                let val = DepositInterestService.calculateInterestToToday(depositInfo: $0)
                                return val > 0 ? NSDecimalNumber(decimal: val).doubleValue : nil
                            },
                            nextPostingDate: account.depositInfo.flatMap {
                                DepositInterestService.nextPostingDate(depositInfo: $0)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.accounts"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Пересчитываем проценты депозитов при открытии экрана (асинхронно)
            depositsViewModel.reconcileAllDeposits(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    transactionsViewModel.addTransaction(transaction)
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        .sheet(isPresented: $showingAddAccount) {
            AccountEditView(
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: nil,
                onSave: { account in
                    HapticManager.success()
                    Task {
                        await accountsViewModel.addAccount(name: account.name, initialBalance: account.initialBalance ?? 0, currency: account.currency, bankLogo: account.bankLogo)
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
                            bankLogo: account.bankLogo,
                            principalBalance: depositInfo.principalBalance,
                            interestRateAnnual: depositInfo.interestRateAnnual,
                            interestPostingDay: depositInfo.interestPostingDay,
                            capitalizationEnabled: depositInfo.capitalizationEnabled
                        )
                        // Reconcile deposits after adding
                        depositsViewModel.reconcileAllDeposits(
                            allTransactions: transactionsViewModel.allTransactions,
                            onTransactionCreated: { transaction in
                                transactionsViewModel.addTransaction(transaction)
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
                let txnsToDelete = transactionsViewModel.allTransactions.filter {
                    $0.accountId == account.id || $0.targetAccountId == account.id
                }

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
    NavigationView {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Accounts Management - Empty") {
    let coordinator = AppCoordinator()
    coordinator.accountsViewModel.accounts = []
    
    return NavigationView {
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
            bankLogo: .kaspi,
            initialBalance: 500000
        ),
        Account(
            id: "preview-2",
            name: "Main Savings",
            currency: "USD",
            bankLogo: .halykBank,
            initialBalance: 15000
        ),
        Account(
            id: "preview-3",
            name: "Halyk Deposit",
            currency: "KZT",
            bankLogo: .halykBank,
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
            bankLogo: .alatauCityBank,
            initialBalance: 2500
        ),
        Account(
            id: "preview-5",
            name: "Jusan Deposit",
            currency: "KZT",
            bankLogo: .jusan,
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

    return List {
        ForEach(sampleAccounts) { account in
            AccountRow(
                account: account,
                currency: account.currency,
                onEdit: {},
                onDelete: {},
                balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!
            )
        }
    }
    .listStyle(PlainListStyle())
}

