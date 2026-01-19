//
//  EditTransactionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct EditTransactionView: View {
    let transaction: Transaction
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
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
    @State private var selectedCurrency: String = ""
    @State private var isRecurring: Bool = false
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var showingRecurringDisableDialog = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var availableCategories: [String] {
        var categories: Set<String> = []
        let transactionType = transaction.type
        
        // Добавляем пользовательские категории нужного типа
        for customCategory in customCategories where customCategory.type == transactionType {
            categories.insert(customCategory.name)
        }
        
        // Добавляем категории из существующих транзакций того же типа
        for tx in transactionsViewModel.allTransactions where tx.type == transactionType {
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
        return categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // 1. Picker (нет в EditTransactionView - тип транзакции не меняется)
                    
                    // 2. Сумма с выбором валюты
                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: showingError ? errorMessage : nil
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    
                    // 3. Счет
                    if !accounts.isEmpty {
                        if transaction.type == .internalTransfer {
                            AccountSelectorView(
                                accounts: accounts,
                                selectedAccountId: $selectedAccountId
                            )
                            
                            AccountSelectorView(
                                accounts: accounts,
                                selectedAccountId: $selectedTargetAccountId
                            )
                            .padding(.top, AppSpacing.md)
                        } else {
                            AccountSelectorView(
                                accounts: accounts,
                                selectedAccountId: $selectedAccountId
                            )
                        }
                    }
                    
                    // 4. Категория
                    if transaction.type != .internalTransfer {
                        CategorySelectorView(
                            categories: availableCategories,
                            type: transaction.type,
                            customCategories: customCategories,
                            selectedCategory: Binding(
                                get: { selectedCategory.isEmpty ? nil : selectedCategory },
                                set: { selectedCategory = $0 ?? "" }
                            ),
                            emptyStateMessage: String(localized: "transactionForm.noCategories")
                        )
                        
                        // 5. Подкатегории
                        if categoryId != nil, !availableSubcategories.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                ForEach(availableSubcategories) { subcategory in
                                    SubcategoryRow(
                                        subcategory: subcategory,
                                        isSelected: Binding(
                                            get: { selectedSubcategoryIds.contains(subcategory.id) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedSubcategoryIds.insert(subcategory.id)
                                                } else {
                                                    selectedSubcategoryIds.remove(subcategory.id)
                                                }
                                            }
                                        ),
                                        onToggle: {
                                            if selectedSubcategoryIds.contains(subcategory.id) {
                                                selectedSubcategoryIds.remove(subcategory.id)
                                            } else {
                                                selectedSubcategoryIds.insert(subcategory.id)
                                            }
                                        }
                                    )
                                }
                                
                                SubcategorySearchButton {
                                    showingSubcategorySearch = true
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        } else if categoryId != nil {
                            SubcategorySearchButton(
                                title: String(localized: "transactionForm.searchAndAddSubcategories")
                            ) {
                                showingSubcategorySearch = true
                            }
                            .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                    
                    // 6. Повтор операции
                    RecurringToggleView(
                        isRecurring: $isRecurring,
                        selectedFrequency: $selectedFrequency
                    )
                    
                    // 7. Описание
                    DescriptionTextField(
                        text: $descriptionText,
                        placeholder: String(localized: "transactionForm.descriptionPlaceholder")
                    )
                }
                .padding(.vertical, AppSpacing.lg)
            }
            .navigationTitle(String(localized: "transactionForm.editTransaction"))
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
            .dateButtonsSafeArea(selectedDate: $selectedDate) { date in
                saveTransaction(date: date)
            }
            .sheet(isPresented: $showingSubcategorySearch) {
                SubcategorySearchView(
                    categoriesViewModel: categoriesViewModel,
                    categoryId: categoryId ?? "",
                    selectedSubcategoryIds: $selectedSubcategoryIds,
                    searchText: $subcategorySearchText
                )
            }
            .onAppear {
                amountText = String(format: "%.2f", transaction.amount)
                descriptionText = transaction.description
                selectedCategory = transaction.category
                selectedAccountId = transaction.accountId
                selectedTargetAccountId = transaction.targetAccountId
                selectedCurrency = transaction.currency
                
                // Загружаем подкатегории из transactionSubcategoryLinks
                let linkedSubcategories = categoriesViewModel.getSubcategoriesForTransaction(transaction.id)
                selectedSubcategoryIds = Set(linkedSubcategories.map { $0.id })
                
                // Проверяем recurring
                // Note: recurringSeries should be accessed through SubscriptionsViewModel
                isRecurring = transaction.recurringSeriesId != nil
                if let seriesId = transaction.recurringSeriesId,
                   let series = transactionsViewModel.recurringSeries.first(where: { $0.id == seriesId }) {
                    selectedFrequency = series.frequency
                }
                
                let dateFormatter = DateFormatters.dateFormatter
                if let date = dateFormatter.date(from: transaction.date) {
                    selectedDate = date
                }
            }
            .onChange(of: isRecurring) { oldValue, newValue in
                if !newValue && transaction.recurringSeriesId != nil {
                    // Если выключаем recurring, отключаем все будущие без подтверждения
                    // Note: stopRecurringSeries should be in SubscriptionsViewModel
                    if let seriesId = transaction.recurringSeriesId {
                        transactionsViewModel.stopRecurringSeries(seriesId)
                    }
                }
            }
            .alert(String(localized: "voice.error"), isPresented: $showingError) {
                Button(String(localized: "voice.ok"), role: .cancel) {}
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
            errorMessage = String(localized: "transactionForm.enterPositiveAmount")
            showingError = true
            HapticManager.warning()
            return
        }
        
        // Валидация для переводов: предотвращаем перевод самому себе
        if transaction.type == .internalTransfer {
            guard let sourceId = selectedAccountId,
                  let targetId = selectedTargetAccountId,
                  sourceId != targetId else {
                errorMessage = String(localized: "transactionForm.cannotTransferToSame")
                showingError = true
                HapticManager.warning()
                return
            }
            
            // Проверяем, что оба счета существуют
            guard accounts.contains(where: { $0.id == sourceId }),
                  accounts.contains(where: { $0.id == targetId }) else {
                errorMessage = String(localized: "transactionForm.accountNotFound")
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
                // Note: createRecurringSeries should be in SubscriptionsViewModel
                let amountDecimal = Decimal(amount)
                let series = transactionsViewModel.createRecurringSeries(
                    amount: amountDecimal,
                    currency: selectedCurrency,
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
                // Note: recurringSeries should be accessed through SubscriptionsViewModel
                if let seriesId = transaction.recurringSeriesId,
                   let seriesIndex = transactionsViewModel.recurringSeries.firstIndex(where: { $0.id == seriesId }) {
                    var series = transactionsViewModel.recurringSeries[seriesIndex]
                    series.amount = Decimal(amount)
                    series.category = selectedCategory
                    series.description = descriptionText.isEmpty ? selectedCategory : descriptionText
                    series.accountId = selectedAccountId
                    series.targetAccountId = selectedTargetAccountId
                    series.frequency = selectedFrequency
                    series.isActive = true // Активируем если была отключена
                    transactionsViewModel.updateRecurringSeries(series)
                }
            }
        } else {
            // Если recurring выключен, но был включен - это обрабатывается через диалог
            // Здесь просто не устанавливаем recurringSeriesId
            finalRecurringSeriesId = nil
            finalRecurringOccurrenceId = nil
        }
        
        // Конвертируем валюту, если она изменилась
        Task {
            var convertedAmount: Double? = nil
            let accountCurrency = accounts.first(where: { $0.id == selectedAccountId })?.currency ?? transaction.currency
            
            if selectedCurrency != accountCurrency {
                convertedAmount = await CurrencyConverter.convert(
                    amount: amount,
                    from: selectedCurrency,
                    to: accountCurrency
                )
            }
            
            await MainActor.run {
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: dateString,
                    description: descriptionText,
                    amount: amount,
                    currency: selectedCurrency,
                    convertedAmount: convertedAmount,
                    type: transaction.type,
                    category: selectedCategory,
                    subcategory: nil,
                    accountId: selectedAccountId,
                    targetAccountId: selectedTargetAccountId,
                    recurringSeriesId: finalRecurringSeriesId,
                    recurringOccurrenceId: finalRecurringOccurrenceId,
                    createdAt: transaction.createdAt // Сохраняем оригинальный createdAt при редактировании
                )
                
                transactionsViewModel.updateTransaction(updatedTransaction)
                
                // Обновляем подкатегории
                categoriesViewModel.linkSubcategoriesToTransaction(
                    transactionId: transaction.id,
                    subcategoryIds: Array(selectedSubcategoryIds)
                )
                
                HapticManager.success()
                dismiss()
            }
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let dateFormatter = DateFormatters.dateFormatter
    let sampleTransaction = Transaction(
        id: "test",
        date: dateFormatter.string(from: Date()),
        description: "Test transaction",
        amount: 1000,
        currency: "KZT",
        type: .expense,
        category: "Food",
        accountId: coordinator.accountsViewModel.accounts.first?.id ?? ""
    )
    NavigationView {
        EditTransactionView(
            transaction: sampleTransaction,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accounts: coordinator.accountsViewModel.accounts,
            customCategories: coordinator.categoriesViewModel.customCategories
        )
    }
}
