//
//  AccountsManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountsManagementView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    
    var body: some View {
        List {
            ForEach(viewModel.accounts) { account in
                AccountRow(
                    account: account,
                    currency: viewModel.appSettings.baseCurrency,
                    onEdit: { editingAccount = account },
                    onDelete: { viewModel.deleteAccount(account) }
                )
                .padding(.horizontal)
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddAccount = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountEditView(
                viewModel: viewModel,
                account: nil,
                onSave: { account in
                    viewModel.addAccount(name: account.name, balance: account.balance, currency: account.currency, bankLogo: account.bankLogo)
                    showingAddAccount = false
                },
                onCancel: { showingAddAccount = false }
            )
        }
        .sheet(item: $editingAccount) { account in
            AccountEditView(
                viewModel: viewModel,
                account: account,
                onSave: { updatedAccount in
                    viewModel.updateAccount(updatedAccount)
                    editingAccount = nil
                },
                onCancel: { editingAccount = nil }
            )
        }
    }
}

struct AccountRow: View {
    let account: Account
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Логотип банка
            account.bankLogo.image(size: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AccountEditView: View {
    @ObservedObject var viewModel: TransactionsViewModel
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
                Section(header: Text("Название")) {
                    TextField("Название счёта", text: $name)
                        .focused($isNameFocused)
                }
                
                Section(header: Text("Логотип банка")) {
                    Button(action: { showingBankLogoPicker = true }) {
                        HStack {
                            Text("Выбрать логотип")
                            Spacer()
                            selectedBankLogo.image(size: 24)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                Section(header: Text("Баланс")) {
                    HStack {
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                        
                        Picker("Валюта", selection: $currency) {
                            ForEach(currencies, id: \.self) { curr in
                                Text(curr).tag(curr)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
            }
            .navigationTitle(account == nil ? "Новый счёт" : "Редактировать счёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
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
                    currency = viewModel.appSettings.baseCurrency
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
                Section(header: Text("Популярные банки")) {
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
                
                Section(header: Text("Другие банки")) {
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
            .navigationTitle("Выбрать логотип")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
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

#Preview {
    AccountsManagementView(viewModel: TransactionsViewModel())
}
