//
//  VoiceInputConfirmationView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct VoiceInputConfirmationView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    
    let parsedOperation: ParsedOperation
    let originalText: String
    
    @State private var selectedType: TransactionType
    @State private var selectedDate: Date
    @State private var amountText: String
    @State private var selectedCurrency: String
    @State private var selectedAccountId: String?
    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryNames: Set<String>
    @State private var noteText: String
    
    @State private var accountWarning: String?
    @State private var amountWarning: String?
    @State private var categoryWarning: String?
    
    init(viewModel: TransactionsViewModel, parsedOperation: ParsedOperation, originalText: String) {
        self.viewModel = viewModel
        self.parsedOperation = parsedOperation
        self.originalText = originalText
        
        _selectedType = State(initialValue: parsedOperation.type)
        _selectedDate = State(initialValue: parsedOperation.date)
        // Парсим сумму - просто конвертируем Decimal в строку без форматирования
        _amountText = State(initialValue: parsedOperation.amount.map { 
            let amountValue = NSDecimalNumber(decimal: $0).doubleValue
            // Используем простой формат без группировки тысяч
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "" // Убираем разделители тысяч
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 0
            formatter.usesGroupingSeparator = false
            return formatter.string(from: NSNumber(value: amountValue)) ?? String(format: "%.2f", amountValue)
        } ?? "")
        _selectedCurrency = State(initialValue: parsedOperation.currencyCode ?? viewModel.accounts.first?.currency ?? "KZT")
        // Устанавливаем счет - сначала из parsedOperation, потом по умолчанию
        let initialAccountId = parsedOperation.accountId ?? viewModel.accounts.first?.id
        _selectedAccountId = State(initialValue: initialAccountId)
        _selectedCategoryName = State(initialValue: parsedOperation.categoryName)
        _selectedSubcategoryNames = State(initialValue: Set(parsedOperation.subcategoryNames))
        _noteText = State(initialValue: parsedOperation.note.isEmpty ? originalText : parsedOperation.note)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Тип операции")) {
                    Picker("Тип", selection: $selectedType) {
                        Text("Расход").tag(TransactionType.expense)
                        Text("Доход").tag(TransactionType.income)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Дата")) {
                    DatePicker("Дата", selection: $selectedDate, displayedComponents: .date)
                }
                
                Section(header: Text("Сумма"), footer: amountWarning.map { Text($0).foregroundColor(.red) }) {
                    HStack {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            // Убрано onChange - валидация только при сохранении или потере фокуса
                            .onChange(of: amountText) {
                                // Очищаем предупреждение при вводе
                                if amountWarning != nil {
                                    amountWarning = nil
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(amountWarning != nil ? Color.red : Color.clear, lineWidth: 1)
                            )
                        
                        Picker("", selection: $selectedCurrency) {
                            ForEach(["KZT", "USD", "EUR", "RUB", "GBP"], id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 80)
                    }
                }
                
                Section(header: Text("Счёт"), footer: accountWarning.map { Text($0).foregroundColor(.orange) }) {
                    if viewModel.accounts.isEmpty {
                        Text("Нет доступных счетов")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.accounts) { account in
                                    AccountRadioButton(
                                        account: account,
                                        isSelected: selectedAccountId == account.id,
                                        onTap: {
                                            selectedAccountId = account.id
                                            validateAccount()
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(accountWarning != nil ? Color.orange : Color.clear, lineWidth: 1)
                        )
                    }
                }
                
                Section(header: Text("Категория"), footer: categoryWarning.map { Text($0).foregroundColor(.orange) }) {
                    Picker("Категория", selection: $selectedCategoryName) {
                        Text("Выберите категорию").tag(nil as String?)
                        ForEach(viewModel.customCategories.filter { $0.type == selectedType }, id: \.name) { category in
                            Text(category.name).tag(category.name as String?)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(categoryWarning != nil ? Color.orange : Color.clear, lineWidth: 1)
                    )
                }
                
                if let categoryName = selectedCategoryName,
                   let category = viewModel.customCategories.first(where: { $0.name == categoryName }),
                   !viewModel.getSubcategoriesForCategory(category.id).isEmpty {
                    Section(header: Text("Подкатегории")) {
                        ForEach(viewModel.getSubcategoriesForCategory(category.id), id: \.id) { subcategory in
                            Toggle(subcategory.name, isOn: Binding(
                                get: { selectedSubcategoryNames.contains(subcategory.name) },
                                set: { isOn in
                                    if isOn {
                                        selectedSubcategoryNames.insert(subcategory.name)
                                    } else {
                                        selectedSubcategoryNames.remove(subcategory.name)
                                    }
                                }
                            ))
                        }
                    }
                }
                
                Section(header: Text("Описание")) {
                    TextField("Описание (необязательно)", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Проверьте операцию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveTransaction()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // Убеждаемся, что счет выбран правильно при появлении
                if selectedAccountId == nil && !viewModel.accounts.isEmpty {
                    selectedAccountId = parsedOperation.accountId ?? viewModel.accounts.first?.id
                }
                validateFields()
            }
            .onChange(of: selectedAccountId) {
                validateAccount()
            }
            .onChange(of: selectedCategoryName) {
                validateCategory()
            }
        }
    }
    
    private var canSave: Bool {
        !amountText.isEmpty && selectedAccountId != nil && selectedCategoryName != nil
    }
    
    private func validateFields() {
        validateAccount()
        validateAmount()
        validateCategory()
    }
    
    private func validateAccount() {
        // Проверяем, что выбранный счет существует
        if let accountId = selectedAccountId {
            if viewModel.accounts.contains(where: { $0.id == accountId }) {
                accountWarning = nil
            } else {
                // Счет не найден, выбираем по умолчанию
                accountWarning = "Счёт не найден — выбран по умолчанию"
                if let defaultAccount = viewModel.accounts.first {
                    selectedAccountId = defaultAccount.id
                }
            }
        } else {
            accountWarning = "Счёт не распознан — выбран по умолчанию"
            // Устанавливаем счет по умолчанию (первый счет)
            if let defaultAccount = viewModel.accounts.first {
                selectedAccountId = defaultAccount.id
            }
        }
    }
    
    private func validateAmount() {
        // Проверка суммы - парсим, убирая валютные символы и пробелы
        let cleanedAmountText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if cleanedAmountText.isEmpty || Double(cleanedAmountText) == nil {
            amountWarning = "Введите сумму"
        } else {
            amountWarning = nil
            // НЕ обновляем amountText автоматически - это вызывает бесконечный цикл обновлений
            // Очистка будет происходить только при сохранении
        }
    }
    
    private func validateCategory() {
        if selectedCategoryName == nil {
            categoryWarning = "Категория не распознана — выбрана по умолчанию"
            // Устанавливаем категорию "Другое"
            if let otherCategory = viewModel.customCategories.first(where: { $0.name == "Другое" && $0.type == selectedType }) {
                selectedCategoryName = otherCategory.name
            } else {
                // Создаем категорию "Другое" если её нет
                let otherCategory = CustomCategory(name: "Другое", iconName: "banknote.fill", colorHex: "#3b82f6", type: selectedType)
                viewModel.addCategory(otherCategory)
                // Ждем обновления списка категорий
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedCategoryName = "Другое"
                }
            }
        } else {
            categoryWarning = nil
        }
    }
    
    private func saveTransaction() {
        // Валидируем перед сохранением
        validateAmount()
        
        // Парсим сумму, убирая валютные символы и пробелы
        let cleanedAmountText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "₸", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Проверяем, что все поля заполнены
        guard let amount = Double(cleanedAmountText), amount > 0 else {
            amountWarning = "Введите корректную сумму"
            return
        }
        
        guard let accountId = selectedAccountId, viewModel.accounts.contains(where: { $0.id == accountId }) else {
            accountWarning = "Выберите счёт"
            // Устанавливаем счет по умолчанию, если не выбран
            if let defaultAccount = viewModel.accounts.first {
                selectedAccountId = defaultAccount.id
                accountWarning = "Счёт не выбран — использован по умолчанию"
            }
            return
        }
        
        // Проверяем и устанавливаем категорию
        var categoryName: String
        if let selectedCategory = selectedCategoryName, 
           viewModel.customCategories.contains(where: { $0.name == selectedCategory && $0.type == selectedType }) {
            categoryName = selectedCategory
        } else {
            categoryWarning = "Выберите категорию"
            // Устанавливаем категорию "Другое", если не выбрана
            if let otherCategory = viewModel.customCategories.first(where: { $0.name == "Другое" && $0.type == selectedType }) {
                selectedCategoryName = otherCategory.name
                categoryName = otherCategory.name
                categoryWarning = "Категория не выбрана — использована по умолчанию"
            } else {
                categoryWarning = "Не удалось найти категорию"
                return
            }
        }
        
        // Получаем валюту счета
        guard let account = viewModel.accounts.first(where: { $0.id == accountId }) else {
            return
        }
        let accountCurrency = account.currency
        
        let dateFormatter = DateFormatters.dateFormatter
        let timeFormatter = DateFormatters.timeFormatter
        let dateString = dateFormatter.string(from: selectedDate)
        let timeString = timeFormatter.string(from: Date())
        
        // Получаем ID подкатегорий (берем первую выбранную)
        var subcategoryId: String? = nil
        if viewModel.customCategories.contains(where: { $0.name == categoryName }),
           let firstSubcategoryName = selectedSubcategoryNames.first {
            subcategoryId = firstSubcategoryName
        }
        
        // Конвертируем валюту, если она отличается от валюты счета
        Task {
            var convertedAmount: Double? = nil
            if selectedCurrency != accountCurrency {
                convertedAmount = await CurrencyConverter.convert(
                    amount: amount,
                    from: selectedCurrency,
                    to: accountCurrency
                )
            }
            
            let transaction = Transaction(
                id: "",
                date: dateString,
                time: timeString,
                description: noteText.isEmpty ? originalText : noteText,
                amount: amount,
                currency: selectedCurrency,
                convertedAmount: convertedAmount,
                type: selectedType,
                category: categoryName,
                subcategory: subcategoryId,
                accountId: accountId,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil
            )
            
            await MainActor.run {
                viewModel.addTransaction(transaction)
                dismiss()
            }
        }
    }
}
