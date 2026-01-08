//
//  AccountActionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountActionView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let account: Account
    @Environment(\.dismiss) var dismiss
    @State private var selectedAction: ActionType = .income
    @State private var amountText: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTargetAccountId: String? = nil
    @FocusState private var isAmountFocused: Bool
    
    enum ActionType {
        case income
        case transfer
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Action")) {
                    Picker("Type", selection: $selectedAction) {
                        Text("Top up").tag(ActionType.income)
                        Text("Transfer").tag(ActionType.transfer)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                if value.translation.width > 0 {
                                    // Свайп вправо - переключить на предыдущий
                                    if selectedAction == .transfer {
                                        selectedAction = .income
                                    }
                                } else {
                                    // Свайп влево - переключить на следующий
                                    if selectedAction == .income {
                                        selectedAction = .transfer
                                    }
                                }
                            }
                    )
                }
                
                if selectedAction == .income {
                    if incomeCategories.isEmpty {
                        Section {
                            Text("No income categories available. Please create categories first.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Section(header: Text("Income category")) {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(incomeCategories, id: \.self) { category in
                                    CategoryRadioButton(
                                        category: category,
                                        isSelected: selectedCategory == category,
                                        viewModel: viewModel,
                                        type: .income,
                                        onTap: {
                                            selectedCategory = category
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } else {
                    if availableAccounts.isEmpty {
                        Section {
                            Text("No other accounts available for transfer")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Section(header: Text("Recipient account")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(availableAccounts) { targetAccount in
                                        AccountRadioButton(
                                            account: targetAccount,
                                            isSelected: selectedTargetAccountId == targetAccount.id,
                                            onTap: {
                                                selectedTargetAccountId = targetAccount.id
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                Section(header: Text("Amount")) {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                }
                
                Section(header: Text("Description")) {
                    TextField("Description (optional)", text: $descriptionText)
                }
            }
            .navigationTitle(selectedAction == .income ? "Top up account" : "Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(amountText.isEmpty || 
                             (selectedAction == .income && (selectedCategory == nil || incomeCategories.isEmpty)) ||
                             (selectedAction == .transfer && (selectedTargetAccountId == nil || availableAccounts.isEmpty)))
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
    }
    
    private var incomeCategories: [String] {
        viewModel.customCategories
            .filter { $0.type == .income }
            .map { $0.name }
            .sorted()
    }
    
    private var availableAccounts: [Account] {
        viewModel.accounts.filter { $0.id != account.id }
    }
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }
    
    private func saveTransaction() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        
        let dateFormatter = DateFormatters.dateFormatter
        let today = dateFormatter.string(from: Date())
        let currentTime = DateFormatters.timeFormatter.string(from: Date())
        
        let finalDescription = descriptionText.isEmpty ? (selectedAction == .income ? "Account top-up" : "Account transfer") : descriptionText
        
        if selectedAction == .income {
            // Пополнение счета
            let transaction = Transaction(
                id: "",
                date: today,
                time: currentTime,
                description: finalDescription,
                amount: amount,
                currency: account.currency,
                type: .income,
                category: selectedCategory ?? "Income",
                subcategory: nil,
                accountId: account.id,
                targetAccountId: nil
            )
            viewModel.addTransaction(transaction)
        } else {
            // Перевод между счетами
            guard let targetAccountId = selectedTargetAccountId else { return }
            let transaction = Transaction(
                id: "",
                date: today,
                time: currentTime,
                description: finalDescription,
                amount: amount,
                currency: account.currency,
                type: .internalTransfer,
                category: "Transfer",
                subcategory: nil,
                accountId: account.id,
                targetAccountId: targetAccountId
            )
            viewModel.addTransaction(transaction)
        }
        
        dismiss()
    }
}

struct CategoryRadioButton: View {
    let category: String
    let isSelected: Bool
    let viewModel: TransactionsViewModel
    let type: TransactionType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? coinColor : coinColor.opacity(0.5))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(emoji)
                            .font(.title)
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? coinBorderColor : Color.clear, lineWidth: 3)
                    )
                
                Text(category)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
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

#Preview {
    AccountActionView(
        viewModel: TransactionsViewModel(),
        account: Account(name: "Main", balance: 1000, currency: "USD")
    )
}
