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
                    onTap: {
                        selectedCategory = category
                        selectedType = .expense
                        showingModal = true
                    }
                )
            }
            
            // Income coin
            CoinView(
                category: "Income",
                type: .income,
                totalText: nil,
                onTap: {
                    selectedCategory = "Income"
                    selectedType = .income
                    showingModal = true
                }
            )
        }
        .sheet(isPresented: $showingModal) {
            AddTransactionModal(
                category: selectedCategory ?? "",
                type: selectedType,
                currency: viewModel.allTransactions.first?.currency ?? "USD",
                accounts: viewModel.accounts,
                onSave: { amount, description, accountId in
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    let transaction = Transaction(
                        id: "",
                        date: today,
                        description: description,
                        amount: amount,
                        currency: viewModel.allTransactions.first?.currency ?? "USD",
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
        if viewModel.popularCategories.isEmpty {
            return [
                "Food", "Transport", "Shopping", "Entertainment",
                "Bills", "Health", "Education", "Travel",
                "Gifts", "Pets", "Groceries", "Coffee", "Subscriptions", "Other"
            ]
        }
        return viewModel.popularCategories
    }
}

struct CoinView: View {
    let category: String
    let type: TransactionType
    let totalText: String?
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
                    
                    if type == .expense, let totalText {
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
        return CategoryColors.hexColor(for: category, opacity: 0.3)
    }
    
    private var coinBorderColor: Color {
        if type == .income {
            return Color.green.opacity(0.6)
        }
        return CategoryColors.hexColor(for: category, opacity: 0.6)
    }
    
    private var emoji: String {
        CategoryEmoji.emoji(for: category, type: type)
    }
}

private enum CategoryEmoji {
    static func emoji(for category: String, type: TransactionType) -> String {
        let key = category.lowercased()
        let map: [String: String] = [
            "income": "💵",
            "food": "🍔",
            "transport": "🚕",
            "shopping": "🛍️",
            "entertainment": "🎉",
            "bills": "💡",
            "health": "🏥",
            "education": "🎓",
            "other": "💰",
            "salary": "💼",
            "delivery": "📦",
            "gifts": "🎁",
            "travel": "✈️",
            "groceries": "🛒",
            "coffee": "☕️",
            "subscriptions": "📺"
        ]
        if let value = map[key] { return value }
        return type == .income ? "💵" : "💰"
    }
}


struct AddTransactionModal: View {
    let category: String
    let type: TransactionType
    let currency: String
    let accounts: [Account]
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
                        Picker("Account", selection: $selectedAccountId) {
                            ForEach(accounts) { account in
                                Text("\(account.name) (\(Formatting.formatCurrency(account.balance, currency: account.currency)))")
                                    .tag(Optional(account.id))
                            }
                        }
                    }
                }
                Section(header: Text("Category")) {
                    Text(category)
                        .foregroundColor(CategoryColors.hexColor(for: category))
                }
                
                Section(header: Text("Amount (\(currency))")) {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                }
                
                Section(header: Text("Description")) {
                    TextField("What was this for?", text: $descriptionText)
                }
            }
            .navigationTitle("Add \(type == .expense ? "Expense" : "Income")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
                           !descriptionText.isEmpty {
                            onSave(amount, descriptionText, selectedAccountId)
                        }
                    }
                    .disabled(amountText.isEmpty || descriptionText.isEmpty)
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


#Preview {
    QuickAddTransactionView(viewModel: TransactionsViewModel())
}
