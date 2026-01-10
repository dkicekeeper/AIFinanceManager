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
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var selectedAction: ActionType = .income
    @State private var amountText: String = ""
    @State private var selectedCurrency: String
    @State private var descriptionText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTargetAccountId: String? = nil
    @State private var selectedDate: Date = Date()
    @State private var showingAccountHistory = false
    @FocusState private var isAmountFocused: Bool
    
    init(viewModel: TransactionsViewModel, account: Account) {
        self.viewModel = viewModel
        self.account = account
        _selectedCurrency = State(initialValue: account.currency)
    }
    
    enum ActionType {
        case income
        case transfer
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Закреплённый фильтр по типу действия
                Picker("Тип", selection: $selectedAction) {
                    Text("Пополнение").tag(ActionType.income)
                    Text("Перевод").tag(ActionType.transfer)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemBackground))
                
                Divider()
                
                Form {
                
                if selectedAction == .income {
                    if incomeCategories.isEmpty {
                        Section {
                            Text("Нет доступных категорий дохода. Создайте категории сначала.")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Section(header: Text("Категория дохода")) {
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
                            Text("Нет других счетов для перевода")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Section(header: Text("Счет получателя")) {
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
                
                Section(header: Text("Сумма")) {
                    HStack {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                        
                        Picker("", selection: $selectedCurrency) {
                            ForEach(["KZT", "USD", "EUR", "RUB", "GBP"], id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 80)
                    }
                }
                
                Section(header: Text("Описание")) {
                    TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
                }
                .padding(.bottom, 0)
                
                // Кнопки даты внизу - сохраняют транзакцию при выборе даты
                DateButtonsView(selectedDate: $selectedDate) { date in
                    saveTransaction(date: date)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(selectedAction == .income ? "Пополнение счета" : "Перевод")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAccountHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingAccountHistory) {
                NavigationView {
                    HistoryView(viewModel: viewModel, initialAccountId: account.id)
                        .environmentObject(timeFilterManager)
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
    
    private func saveTransaction(date: Date) {
        // Проверяем валидность данных перед сохранением
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        guard !amountText.isEmpty else { return }
        
        let dateFormatter = DateFormatters.dateFormatter
        let transactionDate = dateFormatter.string(from: date)
        
        let finalDescription = descriptionText.isEmpty ? (selectedAction == .income ? "Пополнение счета" : "Перевод между счетами") : descriptionText
        
        // Конвертируем валюту, если она отличается от валюты счета
        Task {
            var convertedAmount: Double? = nil
            if selectedCurrency != account.currency {
                convertedAmount = await CurrencyConverter.convert(
                    amount: amount,
                    from: selectedCurrency,
                    to: account.currency
                )
            }
            
            await MainActor.run {
                if selectedAction == .income {
                    // Пополнение счета
                    guard let category = selectedCategory, !incomeCategories.isEmpty else { return }
                    let transaction = Transaction(
                        id: "",
                        date: transactionDate,
                        description: finalDescription,
                        amount: amount,
                        currency: selectedCurrency,
                        convertedAmount: convertedAmount,
                        type: .income,
                        category: category,
                        subcategory: nil,
                        accountId: account.id,
                        targetAccountId: nil
                    )
                    viewModel.addTransaction(transaction)
                } else {
                    // Перевод между счетами
                    guard let targetAccountId = selectedTargetAccountId, !availableAccounts.isEmpty else { return }
                    let transaction = Transaction(
                        id: "",
                        date: transactionDate,
                        description: finalDescription,
                        amount: amount,
                        currency: selectedCurrency,
                        convertedAmount: convertedAmount,
                        type: .internalTransfer,
                        category: "Перевод",
                        subcategory: nil,
                        accountId: account.id,
                        targetAccountId: targetAccountId
                    )
                    viewModel.addTransaction(transaction)
                }
                
                HapticManager.success()
                dismiss()
            }
        }
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
                        Image(systemName: iconName)
                            .font(.title2)
                            .foregroundColor(iconColor)
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
    
    private var iconColor: Color {
        if type == .income {
            return Color.green
        }
        return CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: viewModel.customCategories)
    }
    
    private var iconName: String {
        CategoryEmoji.iconName(for: category, type: type, customCategories: viewModel.customCategories)
    }
}

#Preview {
    AccountActionView(
        viewModel: TransactionsViewModel(),
        account: Account(name: "Main", balance: 1000, currency: "USD", bankLogo: .none)
    )
}
