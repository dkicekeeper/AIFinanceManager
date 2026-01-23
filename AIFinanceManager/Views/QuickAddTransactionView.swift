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
    @State private var showingAddCategory = false

    // Кешированные данные для производительности
    @State private var cachedCategories: [String] = []
    @State private var cachedCategoryExpenses: [String: CategoryExpense] = [:]

    var body: some View {
        let categories = cachedCategories
        let categoryExpenses = cachedCategoryExpenses
        
        Group {
            if categories.isEmpty {
                Button(action: {
                    HapticManager.light()
                    showingAddCategory = true
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(String(localized: "categories.expenseCategories", defaultValue: "Категории расходов"))
                                .font(AppTypography.h3)
                                .foregroundStyle(.primary)
                        }
                        
                        Text(String(localized: "emptyState.noCategories", defaultValue: "Нет категорий"))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardStyle(radius: AppRadius.pill)
                }
                .buttonStyle(.bounce)
            } else {
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
            }
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
                    currency: transactionsViewModel.appSettings.baseCurrency,
                    accounts: accountsViewModel.accounts,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    onDismiss: {
                        selectedCategory = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: nil,
                type: .expense,
                onSave: { category in
                    HapticManager.success()
                    categoriesViewModel.addCategory(category)
                    transactionsViewModel.invalidateCaches()
                    showingAddCategory = false
                },
                onCancel: { showingAddCategory = false }
            )
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
    @ObservedObject var accountsViewModel: AccountsViewModel
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
    
    init(
        category: String,
        type: TransactionType,
        currency: String,
        accounts: [Account],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.category = category
        self.type = type
        self.currency = currency
        self.accounts = accounts
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
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
    
    /// Ранжированный список счетов с учетом частоты использования для данной категории
    private var rankedAccounts: [Account] {
        let amount = AmountFormatter.parse(amountText).map { NSDecimalNumber(decimal: $0).doubleValue }
        
        return accountsViewModel.rankedAccounts(
            transactions: transactionsViewModel.allTransactions,
            type: type,
            amount: amount,
            category: category,
            sourceAccountId: nil
        )
    }
    
    // Убрано computed property formattedAmount - оно вызывалось при каждом обновлении view
    // Форматирование теперь происходит только при сохранении
    
    private var formContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // 1. Picker (нет - категория уже выбрана)
                
                // 2. Сумма с выбором валюты
                AmountInputView(
                    amount: $amountText,
                    selectedCurrency: $selectedCurrency,
                    errorMessage: validationError,
                    onAmountChange: { _ in
                        // Сбросить ошибку при вводе
                        validationError = nil
                    }
                )
                
                // 3. Счет (ранжированный список)
                if !accounts.isEmpty {
                    AccountSelectorView(
                        accounts: rankedAccounts,
                        selectedAccountId: $selectedAccountId
                    )
                }
                
                // 4. Категория (уже выбрана, не показываем)
                
                // 5. Подкатегории
                if categoryId != nil {
                    SubcategorySelectorView(
                        categoriesViewModel: categoriesViewModel,
                        categoryId: categoryId,
                        selectedSubcategoryIds: $selectedSubcategoryIds,
                        onSearchTap: {
                            showingSubcategorySearch = true
                        }
                    )
                }
                
                // 6. Повтор операции
                RecurringToggleView(
                    isRecurring: $isRecurring,
                    selectedFrequency: $selectedFrequency,
                    toggleTitle: String(localized: "quickAdd.makeRecurring"),
                    frequencyTitle: String(localized: "quickAdd.frequency")
                )
                
                // 7. Описание
                DescriptionTextField(
                    text: $descriptionText,
                    placeholder: String(localized: "quickAdd.descriptionPlaceholder")
                )
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
                        .onAppear {
                            // Сбрасываем поиск при открытии, чтобы показать все подкатегории
                            subcategorySearchText = ""
                        }
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
        if selectedAccountId == nil {
            // 🧠 Адаптивное автоподставление счета на основе категории
            if let suggestedAccount = accountsViewModel.suggestedAccount(
                forCategory: category,
                transactions: transactionsViewModel.allTransactions,
                amount: nil // На этом этапе сумма еще неизвестна
            ) {
                print("🎯 [ADAPTIVE] Suggested account '\(suggestedAccount.name)' for category '\(category)'")
                selectedAccountId = suggestedAccount.id
            } else {
                // Fallback - первый счет из списка
                selectedAccountId = accounts.first?.id
            }
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
                // Ищем транзакцию по более точным критериям
                let addedTransaction = transactionsViewModel.allTransactions.first { tx in
                    tx.date == dateString &&
                    tx.description == finalDescription &&
                    tx.amount == amountDouble &&
                    tx.category == category &&
                    tx.accountId == accountId &&
                    tx.type == type
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
