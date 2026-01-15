//
//  TransactionPreviewView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct TransactionPreviewView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    let transactions: [Transaction]
    @Environment(\.dismiss) var dismiss
    @State private var selectedTransactions: Set<String> = Set()
    @State private var accountMapping: [String: String] = [:] // transactionId -> accountId
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Заголовок с информацией
                VStack(spacing: 8) {
                    Text("Найдено транзакций: \(transactions.count)")
                        .font(.headline)
                    Text("Выберите транзакции для добавления")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                
                // Список транзакций
                List {
                    ForEach(transactions) { transaction in
                        TransactionPreviewRow(
                            transaction: transaction,
                            isSelected: selectedTransactions.contains(transaction.id),
                            selectedAccountId: accountMapping[transaction.id],
                            availableAccounts: accountsViewModel.accounts.filter { $0.currency == transaction.currency },
                            onToggle: {
                                if selectedTransactions.contains(transaction.id) {
                                    selectedTransactions.remove(transaction.id)
                                    accountMapping.removeValue(forKey: transaction.id)
                                } else {
                                    selectedTransactions.insert(transaction.id)
                                    // Автоматически выбираем первый подходящий счет
                                    if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                                        accountMapping[transaction.id] = account.id
                                    }
                                }
                            },
                            onAccountSelect: { accountId in
                                accountMapping[transaction.id] = accountId
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())
                
                // Кнопки действий
                HStack(spacing: 12) {
                    Button(action: {
                        selectedTransactions = Set(transactions.map { $0.id })
                        // Автоматически выбираем счета для всех
                        for transaction in transactions {
                            if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                                accountMapping[transaction.id] = account.id
                            }
                        }
                        selectedTransactions = Set(transactions.map { $0.id })
                    }) {
                        Text("Выбрать все")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        selectedTransactions.removeAll()
                        accountMapping.removeAll()
                    }) {
                        Text("Снять выбор")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.gray)
                            .cornerRadius(10)
                    }
                }
                .padding()
                
                // Кнопка добавления
                Button(action: {
                    addSelectedTransactions()
                }) {
                    Text("Добавить выбранные (\(selectedTransactions.count))")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedTransactions.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(selectedTransactions.isEmpty)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Предпросмотр транзакций")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                // По умолчанию выбираем все транзакции
                selectedTransactions = Set(transactions.map { $0.id })
                // Автоматически выбираем счета для всех транзакций
                for transaction in transactions {
                    if let account = accountsViewModel.accounts.first(where: { $0.currency == transaction.currency }) {
                        accountMapping[transaction.id] = account.id
                    }
                }
            }
        }
    }
    
    private func addSelectedTransactions() {
        let transactionsToAdd = transactions.filter { selectedTransactions.contains($0.id) }
        
        for transaction in transactionsToAdd {
            let accountId = accountMapping[transaction.id]
            let updatedTransaction = Transaction(
                id: transaction.id,
                date: transaction.date,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: transaction.category,
                subcategory: transaction.subcategory,
                accountId: accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt // Сохраняем оригинальный createdAt
            )
            transactionsViewModel.addTransaction(updatedTransaction)
        }
        
        dismiss()
    }
}

struct TransactionPreviewRow: View {
    let transaction: Transaction
    let isSelected: Bool
    let selectedAccountId: String?
    let availableAccounts: [Account]
    let onToggle: () -> Void
    let onAccountSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.description)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(transaction.date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(transaction.category)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Formatting.formatCurrency(transaction.amount, currency: transaction.currency))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(transaction.type == .income ? .green : .red)
                    
                    Text(transaction.type == .income ? "Доход" : transaction.type == .expense ? "Расход" : "Перевод")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Выбор счета
            if isSelected && !availableAccounts.isEmpty {
                Picker("Счет", selection: Binding(
                    get: { selectedAccountId ?? "" },
                    set: { onAccountSelect($0) }
                )) {
                    Text("Без счета").tag("")
                    ForEach(availableAccounts) { account in
                        Text("\(account.name) (\(Formatting.currencySymbol(for: account.currency)))").tag(account.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let coordinator = AppCoordinator()
    TransactionPreviewView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        transactions: []
    )
}
