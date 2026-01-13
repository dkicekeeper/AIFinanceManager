//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct QuickAddTransactionView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var selectedCategory: String? = nil
    @State private var selectedType: TransactionType = .expense

    // Кешированные данные для производительности
    @State private var cachedCategories: [String] = []
    @State private var cachedCategoryExpenses: [String: CategoryExpense] = [:]

    var body: some View {
        let categories = cachedCategories
        let categoryExpenses = cachedCategoryExpenses
        
        LazyVGrid(columns: gridColumns, spacing: AppSpacing.lg) {
            ForEach(categories, id: \.self) { category in
                let total = categoryExpenses[category]?.total ?? 0
                let currency = viewModel.appSettings.baseCurrency
                let totalText = total != 0 ? Formatting.formatCurrency(total, currency: currency) : nil

                VStack(spacing: AppSpacing.xs) {
                    CategoryChip(
                        category: category,
                        type: .expense,
                        customCategories: viewModel.customCategories,
                        isSelected: false,
                        onTap: {
                            selectedCategory = category
                            selectedType = .expense
                        }
                    )
                    
                    if let totalText = totalText {
                        Text(totalText)
                            .font(AppTypography.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay(Color.white.opacity(0.001).allowsHitTesting(false))
        .sheet(isPresented: Binding(
            get: { selectedCategory != nil },
            set: { if !$0 { selectedCategory = nil } }
        )) {
            if let category = selectedCategory {
                AddTransactionModal(
                    category: category,
                    type: selectedType,
                    currency: viewModel.appSettings.baseCurrency,
                    accounts: viewModel.accounts,
                    viewModel: viewModel,
                    onDismiss: {
                        selectedCategory = nil
                    }
                )
            }
        }
        .onAppear {
            updateCachedData()
        }
        .onChange(of: viewModel.allTransactions.count) { _, _ in
            updateCachedData()
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            updateCachedData()
        }
        .onChange(of: viewModel.customCategories.count) { _, _ in
            updateCachedData()
        }
    }

    // Обновление кешированных данных
    private func updateCachedData() {
        PerformanceProfiler.start("QuickAddTransactionView.updateCachedData")
        cachedCategoryExpenses = viewModel.categoryExpenses(timeFilterManager: timeFilterManager)
        cachedCategories = popularCategories()
        PerformanceProfiler.end("QuickAddTransactionView.updateCachedData")
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }

    private func popularCategories() -> [String] {
        // Получаем все категории: только пользовательские + из транзакций
        var allCategories = Set<String>()
        
        // Добавляем пользовательские категории расходов
        for customCategory in viewModel.customCategories where customCategory.type == .expense {
            allCategories.insert(customCategory.name)
        }
        
        // Добавляем категории из транзакций (с учетом фильтра по времени)
        let popularFromTransactions = viewModel.popularCategories(timeFilterManager: timeFilterManager)
        for category in popularFromTransactions {
            allCategories.insert(category)
        }
        
        // Сортируем по популярности (сумме расходов с учетом фильтра)
        let categoryExpenses = viewModel.categoryExpenses(timeFilterManager: timeFilterManager)
        return Array(allCategories).sorted { category1, category2 in
            let total1 = categoryExpenses[category1]?.total ?? 0
            let total2 = categoryExpenses[category2]?.total ?? 0
            if total1 != total2 {
                return total1 > total2
            }
            return category1 < category2
        }
    }
}

// CoinView replaced by CategoryChip component


struct AddTransactionModal: View {
    let category: String
    let type: TransactionType
    let currency: String
    let accounts: [Account]
    let viewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    let onDismiss: () -> Void
    
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var selectedAccountId: String?
    @State private var selectedCurrency: String
    @State private var selectedDate: Date = Date()
    @State private var isRecurring = false
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var selectedSubcategoryIds: Set<String> = []
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingCategoryHistory = false
    @State private var isSaving = false
    @State private var validationError: String?
    @FocusState private var isAmountFocused: Bool
    
    init(category: String, type: TransactionType, currency: String, accounts: [Account], viewModel: TransactionsViewModel, onDismiss: @escaping () -> Void) {
        self.category = category
        self.type = type
        self.currency = currency
        self.accounts = accounts
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedCurrency = State(initialValue: currency)
    }
    
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
    
    // Убрано computed property formattedAmount - оно вызывалось при каждом обновлении view
    // Форматирование теперь происходит только при сохранении
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    if !accounts.isEmpty {
                        Section(header: Text("Счёт")) {
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
                    
                    Section(header: Text("Сумма")) {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack {
                                TextField("0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .focused($isAmountFocused)
                                    .onChange(of: amountText) {
                                        // Сбросить ошибку при вводе
                                        validationError = nil
                                    }

                                Picker("", selection: $selectedCurrency) {
                                    ForEach(["KZT", "USD", "EUR", "RUB", "GBP"], id: \.self) { currency in
                                        Text(Formatting.currencySymbol(for: currency)).tag(currency)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 80)
                                .disabled(isSaving)
                            }

                            if let error = validationError {
                                Text(error)
                                    .font(AppTypography.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Section(header: Text("Описание")) {
                        TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    
                    Section(header: Text("Повторяющаяся операция")) {
                        Toggle("Сделать повторяющейся", isOn: $isRecurring)
                        
                        if isRecurring {
                            Picker("Частота", selection: $selectedFrequency) {
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
                DateButtonsView(
                    selectedDate: $selectedDate,
                    isDisabled: isSaving,
                    onSave: { date in
                        saveTransaction(date: date)
                    }
                )
                .padding()
                .background(Color(.systemBackground))
                .overlay(
                    Group {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.5)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.2))
                        }
                    }
                )
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
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
                        .environmentObject(timeFilterManager)
                }
            }
            .onAppear {
                isAmountFocused = true
                if selectedAccountId == nil {
                    selectedAccountId = accounts.first?.id
                }
                // Устанавливаем валюту счета, если счет выбран
                if let accountId = selectedAccountId,
                   let account = accounts.first(where: { $0.id == accountId }) {
                    selectedCurrency = account.currency
                }
            }
            .onChange(of: selectedAccountId) {
                // Обновляем валюту при выборе счета
                if let accountId = selectedAccountId,
                   let account = accounts.first(where: { $0.id == accountId }) {
                    selectedCurrency = account.currency
                }
            }
        }
    }
    
    private func saveTransaction(date: Date) {
        // Валидация суммы
        guard let decimalAmount = AmountFormatter.parse(amountText) else {
            validationError = "Введите корректную сумму"
            HapticManager.error()
            return
        }

        guard decimalAmount > 0 else {
            validationError = "Сумма должна быть больше нуля"
            HapticManager.error()
            return
        }
        
        // Валидация: проверяем, что счет выбран
        guard let accountId = selectedAccountId else {
            validationError = "Выберите счёт"
            HapticManager.error()
            return
        }
        
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            validationError = "Счёт не найден"
            HapticManager.error()
            return
        }

        // Показываем loading
        isSaving = true
        validationError = nil

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: date)
        let finalDescription = descriptionText
        let amountDouble = NSDecimalNumber(decimal: decimalAmount).doubleValue
        let accountCurrency = account.currency
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let transactionDate = calendar.startOfDay(for: date)
        let isFutureDate = transactionDate > today
        
        // Если это recurring, создаем серию
        if isRecurring {
            _ = viewModel.createRecurringSeries(
                amount: decimalAmount,
                currency: selectedCurrency,
                category: category,
                subcategory: nil,
                description: finalDescription,
                accountId: accountId,
                targetAccountId: nil,
                frequency: selectedFrequency,
                startDate: dateString
            )
            
            // Если дата в будущем, транзакция будет создана через generateRecurringTransactions
            // Не создаем её здесь, чтобы избежать дублирования
            if isFutureDate {
                HapticManager.success()
                isSaving = false
                onDismiss()
                return
            }
            // Если дата сегодня или в прошлом - создаем обычную транзакцию (она уже выполнена)
        }

        // Конвертация валюты: предварительно загружаем курсы, если они не в кеше
        Task { @MainActor in
            var convertedAmount: Double? = nil
            if selectedCurrency != accountCurrency {
                // Предварительно загружаем курсы валют для обеих валют
                _ = await CurrencyConverter.getExchangeRate(for: selectedCurrency)
                _ = await CurrencyConverter.getExchangeRate(for: accountCurrency)
                
                // Теперь конвертируем (синхронно, так как курсы уже в кеше)
                convertedAmount = CurrencyConverter.convertSync(
                    amount: amountDouble,
                    from: selectedCurrency,
                    to: accountCurrency
                )
                
                // Если синхронная конвертация не сработала, используем асинхронную
                if convertedAmount == nil {
                    convertedAmount = await CurrencyConverter.convert(
                        amount: amountDouble,
                        from: selectedCurrency,
                        to: accountCurrency
                    )
                }
            }
            
            // Создаем транзакцию
            let transaction = Transaction(
                id: "",
                date: dateString,
                description: finalDescription,
                amount: amountDouble,
                currency: selectedCurrency,
                convertedAmount: convertedAmount,
                type: type,
                category: category,
                subcategory: nil,
                accountId: accountId,
                targetAccountId: nil
            )
            
            viewModel.addTransaction(transaction)
            
            // Связываем подкатегории с транзакцией
            if !selectedSubcategoryIds.isEmpty {
                let addedTransaction = viewModel.allTransactions.first { tx in
                    tx.date == dateString &&
                    tx.description == finalDescription &&
                    tx.amount == amountDouble
                }

                if let transactionId = addedTransaction?.id {
                    viewModel.linkSubcategoriesToTransaction(
                        transactionId: transactionId,
                        subcategoryIds: Array(selectedSubcategoryIds)
                    )
                }
            }
            
            HapticManager.success()
            isSaving = false
            onDismiss()
        }
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
            HStack(spacing: 8) {
                account.bankLogo.image(size: 18)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
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
        .environmentObject(TimeFilterManager())
}
