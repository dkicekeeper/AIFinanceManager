//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct QuickAddTransactionView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @State private var selectedCategory: String?
    @State private var selectedType: TransactionType = .expense
    @State private var showingModal = false
    
    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(popularCategories, id: \.self) { category in
                let total = viewModel.categoryExpenses[category]?.total ?? 0
                let currency = viewModel.allTransactions.first?.currency ?? "USD"
                let totalText = total != 0 ? Formatting.formatCurrency(total, currency: currency) : nil

                CoinView(
                    category: category,
                    type: .expense,
                    totalText: totalText,
                    viewModel: viewModel,
                    onTap: {
                        selectedCategory = category
                        selectedType = .expense
                        showingModal = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingModal) {
            AddTransactionModal(
                category: selectedCategory ?? "",
                type: selectedType,
                currency: viewModel.allTransactions.first?.currency ?? "USD",
                accounts: viewModel.accounts,
                viewModel: viewModel,
                onSave: { amount, description, accountId in
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    let currentTime = timeFormatter.string(from: Date())
                    
                    // Получаем валюту счета или используем дефолтную
                    let currency: String
                    if let accountId = accountId,
                       let account = viewModel.accounts.first(where: { $0.id == accountId }) {
                        currency = account.currency
                    } else {
                        currency = viewModel.allTransactions.first?.currency ?? "USD"
                    }
                    
                    let transaction = Transaction(
                        id: "",
                        date: today,
                        time: currentTime,
                        description: description,
                        amount: amount,
                        currency: currency,
                        type: selectedType,
                        category: selectedCategory ?? "Other",
                        subcategory: nil,
                        accountId: accountId,
                        targetAccountId: nil
                    )
                    
                    viewModel.addTransaction(transaction)
                    selectedCategory = nil
                    showingModal = false
                },
                onCancel: {
                    selectedCategory = nil
                    showingModal = false
                }
            )
        }
    }
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }
    
    private var popularCategories: [String] {
        // Получаем все категории: только пользовательские + из транзакций
        var allCategories = Set<String>()
        
        // Добавляем пользовательские категории расходов
        for customCategory in viewModel.customCategories where customCategory.type == .expense {
            allCategories.insert(customCategory.name)
        }
        
        // Добавляем категории из транзакций
        for category in viewModel.popularCategories {
            allCategories.insert(category)
        }
        
        // Сортируем по популярности (сумме расходов)
        return Array(allCategories).sorted { category1, category2 in
            let total1 = viewModel.categoryExpenses[category1]?.total ?? 0
            let total2 = viewModel.categoryExpenses[category2]?.total ?? 0
            if total1 != total2 {
                return total1 > total2
            }
            return category1 < category2
        }
    }
}

struct CoinView: View {
    let category: String
    let type: TransactionType
    let totalText: String?
    let viewModel: TransactionsViewModel
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(coinColor)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(emoji)
                            .font(.title)
                    )
                    .overlay(
                        Circle()
                            .stroke(coinBorderColor, lineWidth: 2)
                    )
                    .shadow(radius: isPressed ? 2 : 4)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
                
                VStack(spacing: 2) {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if type == .expense {
                        let total = viewModel.categoryExpenses[category]?.total ?? 0
                        let currency = viewModel.allTransactions.first?.currency ?? "USD"
                        let totalText = Formatting.formatCurrency(total, currency: currency)
                        Text(totalText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
    
    private var coinColor: Color {
        if type == .income {
            return Color.green.opacity(0.3)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.3, customCategories: viewModel.customCategories)
    }
    
    private var coinBorderColor: Color {
        if type == .income {
            return Color.green.opacity(0.6)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.6, customCategories: viewModel.customCategories)
    }
    
    private var emoji: String {
        CategoryEmoji.emoji(for: category, type: type, customCategories: viewModel.customCategories)
    }
}


struct AddTransactionModal: View {
    let category: String
    let type: TransactionType
    let currency: String
    let accounts: [Account]
    let viewModel: TransactionsViewModel
    let onSave: (Double, String, String?) -> Void
    let onCancel: () -> Void
    
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var selectedAccountId: String?
    @FocusState private var isAmountFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                if !accounts.isEmpty {
                    Section(header: Text("Account")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(accounts) { account in
                                    AccountRadioButton(
                                        account: account,
                                        isSelected: selectedAccountId == account.id,
                                        onTap: {
                                            selectedAccountId = account.id
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section(header: Text("Amount")) {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                }
                
                        Section(header: Text("Description")) {
                            TextField("What was this for? (optional)", text: $descriptionText)
                        }
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) {
                                    let finalDescription = descriptionText.isEmpty ? category : descriptionText
                                    onSave(amount, finalDescription, selectedAccountId)
                                }
                            }
                            .disabled(amountText.isEmpty)
                }
            }
            .onAppear {
                isAmountFocused = true
                if selectedAccountId == nil {
                    selectedAccountId = accounts.first?.id
                }
            }
        }
    }
}


struct AccountRadioButton: View {
    let account: Account
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(10)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    QuickAddTransactionView(viewModel: TransactionsViewModel())
}
