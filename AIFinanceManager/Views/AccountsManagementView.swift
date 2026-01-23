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
                                accountsViewModel.deleteAccount(account)
                                // CRITICAL: Sync accounts between ViewModels to prevent data loss
                                transactionsViewModel.accounts = accountsViewModel.accounts
                                // Also delete related transactions
                                transactionsViewModel.allTransactions.removeAll {
                                    $0.accountId == account.id || $0.targetAccountId == account.id
                                }
                                transactionsViewModel.recalculateAccountBalances()
                                transactionsViewModel.saveToStorage()
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
                    accountsViewModel.addAccount(name: account.name, balance: account.balance, currency: account.currency, bankLogo: account.bankLogo)
                    // CRITICAL: Sync accounts between ViewModels to prevent data loss
                    transactionsViewModel.accounts = accountsViewModel.accounts
                    transactionsViewModel.recalculateAccountBalances()
                    transactionsViewModel.saveToStorage()
                    showingAddAccount = false
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
                            // CRITICAL: Sync accounts between ViewModels to prevent data loss
                            transactionsViewModel.accounts = accountsViewModel.accounts
                            transactionsViewModel.recalculateAccountBalances()
                            transactionsViewModel.saveToStorage()
                            editingAccount = nil
                        },
                        onCancel: { editingAccount = nil }
                    )
                }
            }
        }
    }
}

struct AccountEditView: View {
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var balanceText: String = ""
    @State private var currency: String = "USD"
    @State private var selectedBankLogo: BankLogo = .none
    @State private var showingBankLogoPicker = false
    @FocusState private var isNameFocused: Bool
    
    private let currencies = ["USD", "EUR", "KZT", "RUB", "GBP"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(String(localized: "common.name"))) {
                    TextField(String(localized: "account.namePlaceholder"), text: $name)
                        .focused($isNameFocused)
                }

                Section(header: Text(String(localized: "common.logo"))) {
                    Button(action: { showingBankLogoPicker = true }) {
                        HStack {
                            Text(String(localized: "account.selectLogo"))
                            Spacer()
                            selectedBankLogo.image(size: 24)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                Section(header: Text(String(localized: "common.balance"))) {
                    HStack {
                        TextField(String(localized: "common.balancePlaceholder"), text: $balanceText)
                            .keyboardType(.decimalPad)
                        
                        Picker(String(localized: "common.currency"), selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(Formatting.currencySymbol(for: curr)).tag(curr)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
            }
            .navigationTitle(account == nil ? String(localized: "modal.newAccount") : String(localized: "modal.editAccount"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.light()
                        // Если balanceText пустой, используем 0 по умолчанию
                        let balance: Double
                        if balanceText.isEmpty {
                            balance = 0.0
                        } else if let parsedBalance = Double(balanceText.replacingOccurrences(of: ",", with: ".")) {
                            balance = parsedBalance
                        } else {
                            balance = 0.0
                        }
                        
                        let newAccount = Account(
                            id: account?.id ?? UUID().uuidString,
                            name: name,
                            balance: balance,
                            currency: currency,
                            bankLogo: selectedBankLogo
                        )
                        onSave(newAccount)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let account = account {
                    name = account.name
                    balanceText = String(format: "%.2f", account.balance)
                    currency = account.currency
                    selectedBankLogo = account.bankLogo
                    isNameFocused = false
                } else {
                    currency = transactionsViewModel.appSettings.baseCurrency
                    selectedBankLogo = .none
                    balanceText = ""
                    // Активируем поле названия при создании нового счета
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                        isNameFocused = true
                    }
                }
            }
            .sheet(isPresented: $showingBankLogoPicker) {
                BankLogoPickerView(selectedLogo: $selectedBankLogo)
            }
        }
    }
}

struct BankLogoPickerView: View {
    @Binding var selectedLogo: BankLogo
    @Environment(\.dismiss) var dismiss
    
    // Группируем банки по категориям для удобства
    private var popularBanks: [BankLogo] {
        [.alatauCityBank, .halykBank, .kaspi, .homeCredit, .eurasian, .forte, .jusan]
    }
    
    private var otherBanks: [BankLogo] {
        BankLogo.allCases.filter { $0 != .none && !popularBanks.contains($0) }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text(String(localized: "account.popularBanks"))) {
                    ForEach(popularBanks) { bank in
                        BankLogoRow(
                            bank: bank,
                            isSelected: selectedLogo == bank,
                            onSelect: {
                                selectedLogo = bank
                                dismiss()
                            }
                        )
                    }
                }

                Section(header: Text(String(localized: "account.otherBanks"))) {
                    ForEach(otherBanks) { bank in
                        BankLogoRow(
                            bank: bank,
                            isSelected: selectedLogo == bank,
                            onSelect: {
                                selectedLogo = bank
                                dismiss()
                            }
                        )
                    }
                }
                
                Section {
                    BankLogoRow(
                        bank: .none,
                        isSelected: selectedLogo == .none,
                        onSelect: {
                            selectedLogo = .none
                            dismiss()
                        }
                    )
                }
            }
            .navigationTitle(String(localized: "navigation.selectLogo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "button.done")) {
                        dismiss()
                    }
                }
            }
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
            balance: 500000,
            currency: "KZT",
            bankLogo: .kaspi
        ),
        Account(
            id: "preview-2",
            name: "Main Savings",
            balance: 15000,
            currency: "USD",
            bankLogo: .halykBank
        ),
        Account(
            id: "preview-3",
            name: "Halyk Deposit",
            balance: 1000000,
            currency: "KZT",
            bankLogo: .halykBank,
            depositInfo: DepositInfo(
                bankName: "Halyk Bank",
                principalBalance: Decimal(1000000),
                capitalizationEnabled: true,
                interestRateAnnual: Decimal(12.5),
                interestPostingDay: 15
            )
        ),
        Account(
            id: "preview-4",
            name: "EUR Account",
            balance: 2500,
            currency: "EUR",
            bankLogo: .alatauCityBank
        ),
        Account(
            id: "preview-5",
            name: "Jusan Deposit",
            balance: 2000000,
            currency: "KZT",
            bankLogo: .jusan,
            depositInfo: DepositInfo(
                bankName: "Jusan Bank",
                principalBalance: Decimal(2000000),
                capitalizationEnabled: false,
                interestRateAnnual: Decimal(10.0),
                interestPostingDay: 1
            )
        )
    ]
    
    return List {
        ForEach(sampleAccounts) { account in
            AccountRow(
                account: account,
                currency: account.currency,
                onEdit: {},
                onDelete: {}
            )
        }
    }
    .listStyle(PlainListStyle())
}

#Preview("Account Edit View - New") {
    let coordinator = AppCoordinator()
    
    return AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Account Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleAccount = Account(
        id: "preview",
        name: "Test Account",
        balance: 10000,
        currency: "USD",
        bankLogo: .kaspi
    )
    
    return AccountEditView(
        accountsViewModel: coordinator.accountsViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        account: sampleAccount,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Bank Logo Picker") {
    @Previewable @State var selectedLogo: BankLogo = .kaspi
    
    return BankLogoPickerView(selectedLogo: $selectedLogo)
}
