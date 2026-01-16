//
//  QuickAddTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct QuickAddTransactionView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
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
                let currency = transactionsViewModel.appSettings.baseCurrency
                let totalText = total != 0 ? Formatting.formatCurrency(total, currency: currency) : nil
                
                // Get custom category for budget info
                let customCategory = categoriesViewModel.customCategories.first { 
                    $0.name.lowercased() == category.lowercased() && $0.type == .expense 
                }
                
                // Calculate budget progress
                let budgetProgress: BudgetProgress? = {
                    if let customCategory = customCategory {
                        return categoriesViewModel.budgetProgress(
                            for: customCategory,
                            transactions: transactionsViewModel.allTransactions
                        )
                    }
                    return nil
                }()

                VStack(spacing: AppSpacing.xs) {
                    CategoryChip(
                        category: category,
                        type: .expense,
                        customCategories: categoriesViewModel.customCategories,
                        isSelected: false,
                        onTap: {
                            selectedCategory = category
                            selectedType = .expense
                        },
                        budgetProgress: budgetProgress,
                        budgetAmount: customCategory?.budgetAmount
                    )
                    
                    if let totalText = totalText {
                        Text(totalText)
                            .font(AppTypography.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Show budget amount if exists
                    if let budgetAmount = customCategory?.budgetAmount {
                        Text(Formatting.formatCurrency(budgetAmount, currency: currency))
                            .font(AppTypography.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        
        .overlay(Color.white.opacity(0.001).allowsHitTesting(false))
        .sheet(isPresented: Binding(
            get: { selectedCategory != nil },
            set: { if !$0 { selectedCategory = nil } }
        )) {
            if let category = selectedCategory {
                AddTransactionModal(
                    category: category,
                    type: selectedType,
                    currency: transactionsViewModel.appSettings.baseCurrency,
                    accounts: accountsViewModel.accounts,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    onDismiss: {
                        selectedCategory = nil
                    }
                )
            }
        }
        .onAppear {
            updateCachedData()
        }
        .onChange(of: transactionsViewModel.allTransactions.count) { _, _ in
            updateCachedData()
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            updateCachedData()
        }
        .onChange(of: categoriesViewModel.customCategories.count) { _, _ in
            updateCachedData()
        }
    }

    // Обновление кешированных данных
    private func updateCachedData() {
        PerformanceProfiler.start("QuickAddTransactionView.updateCachedData")
        cachedCategoryExpenses = transactionsViewModel.categoryExpenses(timeFilterManager: timeFilterManager)
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
        for customCategory in categoriesViewModel.customCategories where customCategory.type == .expense {
            allCategories.insert(customCategory.name)
        }
        
        // Добавляем категории из транзакций (с учетом фильтра по времени)
        let popularFromTransactions = transactionsViewModel.popularCategories(timeFilterManager: timeFilterManager)
        for category in popularFromTransactions {
            allCategories.insert(category)
        }
        
        // Сортируем по популярности (сумме расходов с учетом фильтра)
        let categoryExpenses = transactionsViewModel.categoryExpenses(timeFilterManager: timeFilterManager)
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
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
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
    
    init(
        category: String,
        type: TransactionType,
        currency: String,
        accounts: [Account],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.category = category
        self.type = type
        self.currency = currency
        self.accounts = accounts
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.onDismiss = onDismiss
        _selectedCurrency = State(initialValue: currency)
    }
    
    private var categoryId: String? {
        categoriesViewModel.customCategories.first { $0.name == category }?.id
    }
    
    private var availableSubcategories: [Subcategory] {
        guard let categoryId = categoryId else { return [] }
        return categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }
    
    private var searchResults: [Subcategory] {
        if subcategorySearchText.isEmpty {
            return categoriesViewModel.subcategories
        }
        return categoriesViewModel.searchSubcategories(query: subcategorySearchText)
    }
    
    // Убрано computed property formattedAmount - оно вызывалось при каждом обновлении view
    // Форматирование теперь происходит только при сохранении
    
    private var formContent: some View {
        Form {
                    if !accounts.isEmpty {
                        Section(header: Text(String(localized: "quickAdd.account"))) {
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
                    
                    Section(header: Text(String(localized: "quickAdd.amount"))) {
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
                    
                    Section(header: Text(String(localized: "quickAdd.description"))) {
                        TextField(String(localized: "quickAdd.descriptionPlaceholder"), text: $descriptionText, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    
                    Section(header: Text(String(localized: "quickAdd.recurring"))) {
                        Toggle(String(localized: "quickAdd.makeRecurring"), isOn: $isRecurring)

                        if isRecurring {
                            Picker(String(localized: "quickAdd.frequency"), selection: $selectedFrequency) {
                                ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                                    Text(frequency.displayName).tag(frequency)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    
                    // Подкатегории
                    if categoryId != nil, !availableSubcategories.isEmpty {
                        Section(header: Text(String(localized: "quickAdd.subcategories"))) {
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
                                    Text(String(localized: "quickAdd.searchSubcategories"))
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    } else if categoryId != nil {
                        Section(header: Text(String(localized: "quickAdd.subcategories"))) {
                            Button(action: {
                                showingSubcategorySearch = true
                            }) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(String(localized: "quickAdd.searchAndAddSubcategories"))
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                formContent
                    .sheet(isPresented: $showingSubcategorySearch) {
                        SubcategorySearchView(
                            categoriesViewModel: categoriesViewModel,
                            categoryId: categoryId ?? "",
                            selectedSubcategoryIds: $selectedSubcategoryIds,
                            searchText: $subcategorySearchText
                        )
                    }
            }
            .navigationTitle(category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .dateButtonsSafeArea(
                selectedDate: $selectedDate,
                isDisabled: isSaving,
                onSave: { date in
                    saveTransaction(date: date)
                }
            )
            .overlay(overlayContent)
            .sheet(isPresented: $showingCategoryHistory) {
                categoryHistorySheet
            }
            .onAppear {
                setupOnAppear()
            }
            .onChange(of: selectedAccountId) {
                updateCurrencyForSelectedAccount()
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
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
    }
    
    private var overlayContent: some View {
        Group {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
    
    private var categoryHistorySheet: some View {
        NavigationView {
            HistoryView(
                transactionsViewModel: transactionsViewModel,
                accountsViewModel: AccountsViewModel(repository: transactionsViewModel.repository),
                categoriesViewModel: categoriesViewModel,
                initialCategory: category
            )
                .environmentObject(timeFilterManager)
        }
    }
    
    private func setupOnAppear() {
        isAmountFocused = true
        if selectedAccountId == nil {
            selectedAccountId = accounts.first?.id
        }
        updateCurrencyForSelectedAccount()
    }
    
    private func updateCurrencyForSelectedAccount() {
        if let accountId = selectedAccountId,
           let account = accounts.first(where: { $0.id == accountId }) {
            selectedCurrency = account.currency
        }
    }
    
    private func saveTransaction(date: Date) {
        // Валидация суммы
        guard let decimalAmount = AmountFormatter.parse(amountText) else {
            validationError = String(localized: "error.validation.enterAmount")
            HapticManager.error()
            return
        }

        guard decimalAmount > 0 else {
            validationError = String(localized: "error.validation.amountGreaterThanZero")
            HapticManager.error()
            return
        }

        // Валидация: проверяем, что счет выбран
        guard let accountId = selectedAccountId else {
            validationError = String(localized: "error.validation.selectAccount")
            HapticManager.error()
            return
        }

        guard let account = accounts.first(where: { $0.id == accountId }) else {
            validationError = String(localized: "error.validation.accountNotFound")
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
        // Note: createRecurringSeries should be in SubscriptionsViewModel
        // For now, keeping in TransactionsViewModel for backward compatibility
        if isRecurring {
            _ = transactionsViewModel.createRecurringSeries(
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
            
            transactionsViewModel.addTransaction(transaction)
            
            // Связываем подкатегории с транзакцией
            if !selectedSubcategoryIds.isEmpty {
                let addedTransaction = transactionsViewModel.allTransactions.first { tx in
                    tx.date == dateString &&
                    tx.description == finalDescription &&
                    tx.amount == amountDouble
                }

                if let transactionId = addedTransaction?.id {
                    categoriesViewModel.linkSubcategoriesToTransaction(
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
                DatePicker(String(localized: "quickAdd.selectDate"), selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()

                Spacer()
            }
            .navigationTitle(String(localized: "quickAdd.selectDate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "quickAdd.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "quickAdd.done")) {
                        onDateSelected(selectedDate)
                        dismiss()
                    }
                }
            }
        }
    }
}
#Preview {
    let coordinator = AppCoordinator()
    QuickAddTransactionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel
    )
        .environmentObject(TimeFilterManager())
}
