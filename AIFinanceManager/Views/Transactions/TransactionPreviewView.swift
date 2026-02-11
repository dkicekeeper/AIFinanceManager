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
    @EnvironmentObject var transactionStore: TransactionStore // Phase 7.5: TransactionStore integration
    let transactions: [Transaction]
    @Environment(\.dismiss) var dismiss
    @State private var selectedTransactions: Set<String> = Set()
    @State private var accountMapping: [String: String] = [:] // transactionId -> accountId
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Заголовок с информацией
                VStack(spacing: AppSpacing.sm) {
                    Text("Найдено транзакций: \(transactions.count)")
                        .font(AppTypography.h4)
                    Text("Выберите транзакции для добавления")
                        .font(AppTypography.bodySecondary)
                        .foregroundColor(AppColors.textSecondary)
                }
                .cardContentPadding()
                .frame(maxWidth: .infinity)
                .background(AppColors.surface)

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
                HStack(spacing: AppSpacing.md) {
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
                            .padding(AppSpacing.md)
                            .background(AppColors.accent.opacity(0.1))
                            .foregroundColor(AppColors.accent)
                            .cornerRadius(AppRadius.button)
                    }

                    Button(action: {
                        selectedTransactions.removeAll()
                        accountMapping.removeAll()
                    }) {
                        Text("Снять выбор")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.textSecondary)
                            .cornerRadius(AppRadius.button)
                    }
                }
                .cardContentPadding()

                // Кнопка добавления
                Button(action: {
                    addSelectedTransactions()
                }) {
                    Text("Добавить выбранные (\(selectedTransactions.count))")
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(selectedTransactions.isEmpty ? AppColors.secondaryBackground : AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(AppRadius.button)
                }
                .disabled(selectedTransactions.isEmpty)
                .screenPadding()
                .padding(.bottom, AppSpacing.md)
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

        // Phase 7.5: Use TransactionStore for bulk add operation
        Task {
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
                    createdAt: transaction.createdAt
                )

                do {
                    try await transactionStore.add(updatedTransaction)
                } catch {
                    print("❌ Failed to add transaction: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                dismiss()
            }
        }
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? AppColors.accent : AppColors.textSecondary)
                        .font(AppTypography.h4)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(transaction.description)
                        .font(AppTypography.bodyPrimary)
                        .fontWeight(.medium)

                    Text(transaction.date)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Text(transaction.category)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColors.accent.opacity(0.1))
                        .cornerRadius(AppRadius.xs)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    FormattedAmountText(
                        amount: transaction.amount,
                        currency: transaction.currency,
                        fontSize: AppTypography.amount,
                        color: transaction.type == .income ? AppColors.income : AppColors.expense
                    )

                    Text(transaction.type == .income ? "Доход" : transaction.type == .expense ? "Расход" : "Перевод")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
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
