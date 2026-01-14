//
//  EditTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct EditTransactionView: View {
    let transaction: Transaction
    @ObservedObject var viewModel: TransactionsViewModel
    let accounts: [Account]
    let customCategories: [CustomCategory]
    @Environment(\.dismiss) var dismiss
    
    @State private var amountText: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedCategory: String = ""
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var selectedAccountId: String? = nil
    @State private var selectedTargetAccountId: String? = nil
    @State private var selectedDate: Date = Date()
    @State private var isRecurring: Bool = false
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingRecurringDisableDialog = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isAmountFocused: Bool
    
    private var availableCategories: [String] {
        var categories: Set<String> = []
        let transactionType = transaction.type
        
        // Добавляем пользовательские категории нужного типа
        for customCategory in customCategories where customCategory.type == transactionType {
            categories.insert(customCategory.name)
        }
        
        // Добавляем категории из существующих транзакций того же типа
        for tx in viewModel.allTransactions where tx.type == transactionType {
            if !tx.category.isEmpty && tx.category != "Uncategorized" {
                categories.insert(tx.category)
            }
        }
        
        // Если категория текущей транзакции не найдена, добавляем её
        if !transaction.category.isEmpty && transaction.category != "Uncategorized" {
            categories.insert(transaction.category)
        }
        
        // Добавляем "Uncategorized" если нет категорий
        if categories.isEmpty {
            categories.insert("Uncategorized")
        }
        
        return Array(categories).sorted()
    }
    
    private var categoryId: String? {
        customCategories.first { $0.name == selectedCategory }?.id
    }
    
    private var availableSubcategories: [Subcategory] {
        guard let categoryId = categoryId else { return [] }
        return viewModel.getSubcategoriesForCategory(categoryId)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    if !accounts.isEmpty {
                        Section(header: Text("Account")) {
                            if transaction.type == .internalTransfer {
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
                                
                                Section(header: Text("To Account")) {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(accounts) { account in
                                                AccountRadioButton(
                                                    account: account,
                                                    isSelected: selectedTargetAccountId == account.id,
                                                    onTap: {
                                                        selectedTargetAccountId = account.id
                                                    }
                                                )
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            } else {
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
                    }
                    
                    Section(header: Text("Amount")) {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                    }
                    
                    Section(header: Text("Description")) {
                        TextField("What was this for? (optional)", text: $descriptionText)
                    }
                    
                    if transaction.type != .internalTransfer {
                        Section(header: Text("Category")) {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(availableCategories, id: \.self) { category in
                                    Text(category).tag(category)
                                }
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
                }
                .sheet(isPresented: $showingSubcategorySearch) {
                    SubcategorySearchView(
                        viewModel: viewModel,
                        categoryId: categoryId ?? "",
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        searchText: $subcategorySearchText
                    )
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveTransaction(date: selectedDate)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .dateButtonsToolbar(selectedDate: $selectedDate) { date in
                saveTransaction(date: date)
            }
            .onAppear {
                amountText = String(format: "%.2f", transaction.amount)
                descriptionText = transaction.description
                selectedCategory = transaction.category
                selectedAccountId = transaction.accountId
                selectedTargetAccountId = transaction.targetAccountId
                
                // Загружаем подкатегории из transactionSubcategoryLinks
                let linkedSubcategories = viewModel.getSubcategoriesForTransaction(transaction.id)
                selectedSubcategoryIds = Set(linkedSubcategories.map { $0.id })
                
                // Проверяем recurring
                isRecurring = transaction.recurringSeriesId != nil
                if let seriesId = transaction.recurringSeriesId,
                   let series = viewModel.recurringSeries.first(where: { $0.id == seriesId }) {
                    selectedFrequency = series.frequency
                }
                
                let dateFormatter = DateFormatters.dateFormatter
                if let date = dateFormatter.date(from: transaction.date) {
                    selectedDate = date
                }
                
                isAmountFocused = false
            }
            .onChange(of: isRecurring) { oldValue, newValue in
                if !newValue && transaction.recurringSeriesId != nil {
                    // Если выключаем recurring, отключаем все будущие без подтверждения
                    if let seriesId = transaction.recurringSeriesId {
                        viewModel.stopRecurringSeries(seriesId)
                    }
                }
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveTransaction(date: Date) {
        // Валидация: проверяем, что сумма введена и положительна
        guard !amountText.isEmpty,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            errorMessage = "Введите положительную сумму"
            showingError = true
            HapticManager.warning()
            return
        }
        
        // Валидация для переводов: предотвращаем перевод самому себе
        if transaction.type == .internalTransfer {
            guard let sourceId = selectedAccountId,
                  let targetId = selectedTargetAccountId,
                  sourceId != targetId else {
                errorMessage = "Нельзя перевести средства на тот же счет"
                showingError = true
                HapticManager.warning()
                return
            }
            
            // Проверяем, что оба счета существуют
            guard accounts.contains(where: { $0.id == sourceId }),
                  accounts.contains(where: { $0.id == targetId }) else {
                errorMessage = "Один из счетов не найден"
                showingError = true
                HapticManager.error()
                return
            }
        }
        
        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: date)
        
        // Обработка recurring
        var finalRecurringSeriesId: String? = transaction.recurringSeriesId
        var finalRecurringOccurrenceId: String? = transaction.recurringOccurrenceId
        
        if isRecurring {
            if transaction.recurringSeriesId == nil {
                // Создаем новую recurring серию
                let amountDecimal = Decimal(amount)
                let series = viewModel.createRecurringSeries(
                    amount: amountDecimal,
                    currency: transaction.currency,
                    category: selectedCategory,
                    subcategory: nil,
                    description: descriptionText.isEmpty ? selectedCategory : descriptionText,
                    accountId: selectedAccountId,
                    targetAccountId: selectedTargetAccountId,
                    frequency: selectedFrequency,
                    startDate: dateString
                )
                finalRecurringSeriesId = series.id
            } else {
                // Обновляем существующую серию
                if let seriesId = transaction.recurringSeriesId,
                   let seriesIndex = viewModel.recurringSeries.firstIndex(where: { $0.id == seriesId }) {
                    var series = viewModel.recurringSeries[seriesIndex]
                    series.amount = Decimal(amount)
                    series.category = selectedCategory
                    series.description = descriptionText.isEmpty ? selectedCategory : descriptionText
                    series.accountId = selectedAccountId
                    series.targetAccountId = selectedTargetAccountId
                    series.frequency = selectedFrequency
                    series.isActive = true // Активируем если была отключена
                    viewModel.updateRecurringSeries(series)
                }
            }
        } else {
            // Если recurring выключен, но был включен - это обрабатывается через диалог
            // Здесь просто не устанавливаем recurringSeriesId
            finalRecurringSeriesId = nil
            finalRecurringOccurrenceId = nil
        }
        
        let updatedTransaction = Transaction(
            id: transaction.id,
            date: dateString,
            description: descriptionText,
            amount: amount,
            currency: transaction.currency,
            type: transaction.type,
            category: selectedCategory,
            subcategory: nil,
            accountId: selectedAccountId,
            targetAccountId: selectedTargetAccountId,
            recurringSeriesId: finalRecurringSeriesId,
            recurringOccurrenceId: finalRecurringOccurrenceId,
            createdAt: transaction.createdAt // Сохраняем оригинальный createdAt при редактировании
        )
        
        viewModel.updateTransaction(updatedTransaction)
        
        // Обновляем подкатегории
        viewModel.linkSubcategoriesToTransaction(
            transactionId: transaction.id,
            subcategoryIds: Array(selectedSubcategoryIds)
        )
        
        HapticManager.success()
        dismiss()
    }
}

#Preview {
    let viewModel = TransactionsViewModel()
    let dateFormatter = DateFormatters.dateFormatter
    let sampleTransaction = Transaction(
        id: "test",
        date: dateFormatter.string(from: Date()),
        description: "Test transaction",
        amount: 1000,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: viewModel.accounts.first?.id ?? ""
    )
    NavigationView {
        EditTransactionView(
            transaction: sampleTransaction,
            viewModel: viewModel,
            accounts: viewModel.accounts,
            customCategories: viewModel.customCategories
        )
    }
}
