//
//  AccountsManagementView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountsManagementView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var showingAddAccount = false
    @State private var editingAccount: Account?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.accounts) { account in
                        AccountRow(
                            account: account,
                            currency: viewModel.allTransactions.first?.currency ?? account.currency,
                            onEdit: { editingAccount = account },
                            onDelete: { viewModel.deleteAccount(account) }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
                        viewModel.addAccount(name: account.name, balance: account.balance, currency: account.currency)
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
}

struct AccountRow: View {
    let account: Account
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
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
    
    private let currencies = ["USD", "EUR", "KZT", "RUB", "GBP"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Название")) {
                    TextField("Название счёта", text: $name)
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
                        if let balance = Double(balanceText.replacingOccurrences(of: ",", with: ".")) {
                            let newAccount = Account(
                                id: account?.id ?? UUID().uuidString,
                                name: name,
                                balance: balance,
                                currency: currency
                            )
                            onSave(newAccount)
                        }
                    }
                    .disabled(name.isEmpty || balanceText.isEmpty)
                }
            }
            .onAppear {
                if let account = account {
                    name = account.name
                    balanceText = String(format: "%.2f", account.balance)
                    currency = account.currency
                } else {
                    currency = viewModel.allTransactions.first?.currency ?? "USD"
                }
            }
        }
    }
}

#Preview {
    AccountsManagementView(viewModel: TransactionsViewModel())
}
