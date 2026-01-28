//
//  AddTransactionModal.swift
//  AIFinanceManager
//
//  Modal form for adding a transaction from the QuickAdd category grid.
//

import SwiftUI

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

    private var formContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                AmountInputView(
                    amount: $amountText,
                    selectedCurrency: $selectedCurrency,
                    errorMessage: validationError,
                    onAmountChange: { _ in
                        validationError = nil
                    }
                )

                if !accounts.isEmpty {
                    AccountSelectorView(
                        accounts: rankedAccounts,
                        selectedAccountId: $selectedAccountId
                    )
                }

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

                RecurringToggleView(
                    isRecurring: $isRecurring,
                    selectedFrequency: $selectedFrequency,
                    toggleTitle: String(localized: "quickAdd.makeRecurring"),
                    frequencyTitle: String(localized: "quickAdd.frequency")
                )

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
            if let suggestedAccount = accountsViewModel.suggestedAccount(
                forCategory: category,
                transactions: transactionsViewModel.allTransactions,
                amount: nil
            ) {
                selectedAccountId = suggestedAccount.id
            } else {
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

            if isFutureDate {
                HapticManager.success()
                isSaving = false
                onDismiss()
                return
            }
        }

        Task { @MainActor in
            var convertedAmount: Double? = nil
            if selectedCurrency != accountCurrency {
                _ = await CurrencyConverter.getExchangeRate(for: selectedCurrency)
                _ = await CurrencyConverter.getExchangeRate(for: accountCurrency)

                convertedAmount = CurrencyConverter.convertSync(
                    amount: amountDouble,
                    from: selectedCurrency,
                    to: accountCurrency
                )

                if convertedAmount == nil {
                    convertedAmount = await CurrencyConverter.convert(
                        amount: amountDouble,
                        from: selectedCurrency,
                        to: accountCurrency
                    )
                }
            }

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

            if !selectedSubcategoryIds.isEmpty {
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
