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
    
    var body: some View {
        List {
            ForEach(accountsViewModel.accounts) { account in
                AccountRow(
                    account: account,
                    currency: transactionsViewModel.appSettings.baseCurrency,
                    onEdit: { editingAccount = account },
                    onDelete: { 
                        accountsViewModel.deleteAccount(account)
                        // Also delete related transactions
                        transactionsViewModel.allTransactions.removeAll { 
                            $0.accountId == account.id || $0.targetAccountId == account.id 
                        }
                        transactionsViewModel.recalculateAccountBalances()
                    }
                )
//                .padding(.horizontal, AppSpacing.lg)
//                .padding(.vertical, AppSpacing.xs)
//                .listRowInsets(EdgeInsets())
//                .listRowSeparator(.hidden)
            }
        }
//        .listStyle(PlainListStyle())
        .navigationTitle(String(localized: "settings.accounts"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Пересчитываем проценты депозитов при открытии экрана
            depositsViewModel.reconcileAllDeposits(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    transactionsViewModel.addTransaction(transaction)
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button(action: { showingAddAccount = true }) {
                        Label("Новый счёт", systemImage: "creditcard")
                    }
                    Button(action: { showingAddDeposit = true }) {
                        Label("Новый депозит", systemImage: "banknote")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .tint(.blue)
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountEditView(
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: nil,
                onSave: { account in
                    accountsViewModel.addAccount(name: account.name, balance: account.balance, currency: account.currency, bankLogo: account.bankLogo)
                    transactionsViewModel.recalculateAccountBalances()
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
                            accountsViewModel.updateAccount(updatedAccount)
                            transactionsViewModel.recalculateAccountBalances()
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
                    TextField("Название счёта", text: $name)
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
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                        
                        Picker("Валюта", selection: $currency) {
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

struct BankLogoRow: View {
    let bank: BankLogo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                bank.image(size: 40)
                    .frame(width: 40, height: 40)
                
                Text(bank.displayName)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
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

#Preview("Account Row") {
    let coordinator = AppCoordinator()
    let sampleAccount = coordinator.accountsViewModel.accounts.first ?? Account(
        id: "preview",
        name: "Sample Account",
        balance: 10000,
        currency: "KZT",
        bankLogo: .kaspi
    )
    
    List {
        AccountRow(
            account: sampleAccount,
            currency: "KZT",
            onEdit: {},
            onDelete: {}
        )
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
