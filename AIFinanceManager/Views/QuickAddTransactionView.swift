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
                onSave: { amount, description, accountId, dateString, subcategoryIds in
                    let currentTime = DateFormatters.timeFormatter.string(from: Date())
                    
                    // Получаем валюту счета или используем дефолтную
                    let currency: String
                    if let accountId = accountId,
                       let account = viewModel.accounts.first(where: { $0.id == accountId }) {
                        currency = account.currency
                    } else {
                        currency = viewModel.allTransactions.first?.currency ?? "USD"
                    }
                    
                    // Конвертируем Decimal в Double для Transaction
                    let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
                    
                    let transaction = Transaction(
                        id: "",
                        date: dateString,
                        time: currentTime,
                        description: description,
                        amount: amountDouble,
                        currency: currency,
                        type: selectedType,
                        category: selectedCategory ?? "Other",
                        subcategory: nil,
                        accountId: accountId,
                        targetAccountId: nil
                    )
                    
                    viewModel.addTransaction(transaction)
                    
                    // Связываем подкатегории с транзакцией
                    if !subcategoryIds.isEmpty {
                        // Получаем ID транзакции после добавления
                        let addedTransaction = viewModel.allTransactions.first { tx in
                            tx.date == dateString &&
                            tx.description == description &&
                            tx.amount == amountDouble
                        }
                        
                        if let transactionId = addedTransaction?.id {
                            viewModel.linkSubcategoriesToTransaction(
                                transactionId: transactionId,
                                subcategoryIds: Array(subcategoryIds)
                            )
                        }
                    }
                    
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
    let onSave: (Decimal, String, String?, String, Set<String>) -> Void // amount, description, accountId, date, subcategoryIds
    let onCancel: () -> Void
    
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var selectedAccountId: String?
    @State private var selectedDate: Date = Date()
    @State private var showingDatePicker = false
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingCategoryHistory = false
    @FocusState private var isAmountFocused: Bool
    
    private var categoryId: String? {
        viewModel.customCategories.first { $0.name == category }?.id
    }
    
    private var availableSubcategories: [Subcategory] {
        guard let categoryId = categoryId else { return [] }
        return viewModel.getSubcategoriesForCategory(categoryId)
    }
    
    private var searchResults: [Subcategory] {
        if subcategorySearchText.isEmpty {
            return viewModel.subcategories
        }
        return viewModel.searchSubcategories(query: subcategorySearchText)
    }
    
    private var formattedAmount: String {
        if let decimal = AmountFormatter.parse(amountText) {
            return AmountFormatter.format(decimal)
        }
        return amountText
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
                    
                    Section(header: Text("Recurring")) {
                        Toggle("Make this recurring", isOn: $isRecurring)
                        
                        if isRecurring {
                            Picker("Frequency", selection: $selectedFrequency) {
                                ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                                    Text(frequency.displayName).tag(frequency)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    
                    // Подкатегории
                    if categoryId != nil, !availableSubcategories.isEmpty {
                        Section(header: Text("Подкатегории")) {
                            ForEach(availableSubcategories) { subcategory in
                                HStack {
                                    Text(subcategory.name)
                                    Spacer()
                                    if selectedSubcategoryIds.contains(subcategory.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedSubcategoryIds.contains(subcategory.id) {
                                        selectedSubcategoryIds.remove(subcategory.id)
                                    } else {
                                        selectedSubcategoryIds.insert(subcategory.id)
                                    }
                                }
                            }
                            
                            Button(action: {
                                showingSubcategorySearch = true
                            }) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text("Поиск подкатегорий")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    } else if categoryId != nil {
                        Section(header: Text("Подкатегории")) {
                            Button(action: {
                                showingSubcategorySearch = true
                            }) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text("Поиск и добавление подкатегорий")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingSubcategorySearch) {
                    SubcategorySearchView(
                        viewModel: viewModel,
                        categoryId: categoryId ?? "",
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        searchText: $subcategorySearchText
                    )
                }
                
                // Кнопки даты внизу
                HStack(spacing: 12) {
                    Button(action: {
                        selectedDate = Date()
                        saveTransaction(date: selectedDate)
                    }) {
                        Text("Сегодня")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                            selectedDate = yesterday
                            saveTransaction(date: yesterday)
                        }
                    }) {
                        Text("Вчера")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        showingDatePicker = true
                    }) {
                        Text("Календарь")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCategoryHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingCategoryHistory) {
                NavigationView {
                    HistoryView(viewModel: viewModel, initialCategory: category)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(selectedDate: $selectedDate) { date in
                    saveTransaction(date: date)
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
    
    private func saveTransaction(date: Date) {
        guard let decimalAmount = AmountFormatter.parse(amountText) else {
            return
        }
        
        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: date)
        
        let finalDescription = descriptionText
        
        // Если это recurring, создаем серию
        if isRecurring {
            _ = viewModel.createRecurringSeries(
                amount: decimalAmount,
                currency: currency,
                category: category,
                subcategory: nil,
                description: finalDescription,
                accountId: selectedAccountId,
                targetAccountId: nil,
                frequency: selectedFrequency,
                startDate: dateString
            )
        }
        
        onSave(decimalAmount, finalDescription, selectedAccountId, dateString, selectedSubcategoryIds)
    }
}

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker("Выберите дату", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Выберите дату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        onDateSelected(selectedDate)
                        dismiss()
                    }
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
