//
//  AccountActionView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore // Phase 7.4: TransactionStore integration
    @Environment(AppCoordinator.self) private var appCoordinator
    let account: Account
    @Environment(\.dismiss) var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var selectedAction: ActionType = .transfer
    @State private var amountText: String = ""
    @State private var selectedCurrency: String
    @State private var descriptionText: String = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTargetAccountId: String? = nil
    @State private var selectedDate: Date = Date()
    @State private var showingAccountHistory = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isAmountFocused: Bool
    
    let transferDirection: DepositTransferDirection? // nil для обычных счетов, .toDeposit для пополнения, .fromDeposit для вывода
    
    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        account: Account,
        transferDirection: DepositTransferDirection? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.account = account
        self.transferDirection = transferDirection
        _selectedCurrency = State(initialValue: account.currency)
        // Для депозитов всегда используем перевод
        _selectedAction = State(initialValue: account.isDeposit ? .transfer : .transfer)
    }
    
    enum ActionType {
        case income
        case transfer
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // 1. Picker типа действия (если есть)
                    if !account.isDeposit {
                        SegmentedPickerView(
                            title: String(localized: "common.type"),
                            selection: $selectedAction,
                            options: [
                                (label: String(localized: "transactionForm.transfer"), value: ActionType.transfer),
                                (label: String(localized: "transactionForm.topUp"), value: ActionType.income)
                            ]
                        )
                        .padding(AppSpacing.lg)
                    }
                    
                    // 2. Сумма с выбором валюты
                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: showingError ? errorMessage : nil,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency
                    )
                    
                    // 3. Счет
                    if selectedAction == .income && !account.isDeposit {
                        // Для пополнения счет не нужен
                        EmptyView()
                    } else {
                        AccountSelectorView(
                            accounts: availableAccounts,
                            selectedAccountId: $selectedTargetAccountId,
                            emptyStateMessage: String(localized: "transactionForm.noAccountsForTransfer"),
                            balanceCoordinator: accountsViewModel.balanceCoordinator!
                        )
                    }
                    
                    // 4. Категория (только для пополнения)
                    if selectedAction == .income && !account.isDeposit {
                        CategorySelectorView(
                            categories: incomeCategories,
                            type: .income,
                            customCategories: transactionsViewModel.customCategories,
                            selectedCategory: $selectedCategory,
                            emptyStateMessage: String(localized: "transactionForm.noCategories")
                        )
                    }
                    
                    // 5. Подкатегории (нет в AccountActionView)
                    
                    // 6. Повтор операции (нет в AccountActionView)
                    
                    // 7. Описание
                    DescriptionTextField(
                        text: $descriptionText,
                        placeholder: String(localized: "transactionForm.descriptionPlaceholder")
                    )
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
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
            .dateButtonsSafeArea(selectedDate: $selectedDate, onSave: { date in
                saveTransaction(date: date)
            })
            .sheet(isPresented: $showingAccountHistory) {
                NavigationStack {
                    HistoryView(
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: accountsViewModel,
                        categoriesViewModel: CategoriesViewModel(repository: transactionsViewModel.repository),
                        paginationController: appCoordinator.transactionPaginationController,
                        initialAccountId: account.id
                    )
                        .environment(timeFilterManager)
                }
            }
            .onAppear {
                // Фокус теперь управляется внутри AmountInputView
            }
            .alert(String(localized: "voice.error"), isPresented: $showingError) {
                Button(String(localized: "voice.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var incomeCategories: [String] {
        transactionsViewModel.incomeCategories
    }
    
    private var availableAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != account.id }
    }
    
    private var headerForAccountSelection: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit ? String(localized: "transactionForm.fromAccount") : String(localized: "transactionForm.toAccount")
            }
            return String(localized: "transactionForm.fromAccount")
        }
        return String(localized: "transactionForm.toAccount")
    }
    
    private var navigationTitleText: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit ? String(localized: "transactionForm.depositTopUp") : String(localized: "transactionForm.depositWithdrawal")
            }
            return String(localized: "transactionForm.depositTopUp")
        }
        return selectedAction == .income ? String(localized: "transactionForm.accountTopUp") : String(localized: "transactionForm.transfer")
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
        
        let dateFormatter = DateFormatters.dateFormatter
        let transactionDate = dateFormatter.string(from: date)
        
        // Для переводов не устанавливаем дефолтное описание, если оно не заполнено
        let finalDescription = descriptionText.isEmpty ? (selectedAction == .income ? String(localized: "transactionForm.accountTopUp") : "") : descriptionText
        
        // Конвертируем валюту, если она отличается от валюты счета
        Task {
            var convertedAmount: Double? = nil
            
            if selectedAction == .income {
                // Для пополнения конвертируем только в валюту счета
                if selectedCurrency != account.currency {
                    guard let converted = await CurrencyConverter.convert(
                        amount: amount,
                        from: selectedCurrency,
                        to: account.currency
                    ) else {
                        await MainActor.run {
                            errorMessage = "Ошибка конвертации валюты. Проверьте подключение к интернету."
                            showingError = true
                            HapticManager.error()
                        }
                        return
                    }
                    convertedAmount = converted
                }
            } else {
                // Для перевода: конвертируем для источника
                // Для депозитов: источник зависит от направления перевода
                //   - .toDeposit: источник = selectedTargetAccountId (счет, с которого пополняем)
                //   - .fromDeposit: источник = account.id (сам депозит)
                // Для обычных счетов: источник = account
                let sourceAccountId: String?
                if account.isDeposit {
                    if let direction = transferDirection {
                        sourceAccountId = direction == .toDeposit ? selectedTargetAccountId : account.id
                    } else {
                        sourceAccountId = selectedTargetAccountId // Fallback для обратной совместимости
                    }
                } else {
                    sourceAccountId = account.id
                }
                
                let sourceCurrency: String? = await MainActor.run {
                    if account.isDeposit, let direction = transferDirection {
                        if direction == .fromDeposit {
                            // Для вывода с депозита источник - сам депозит
                            return account.currency
                        } else if let sourceId = selectedTargetAccountId {
                            // Для пополнения депозита источник - выбранный счет
                            return accountsViewModel.accounts.first(where: { $0.id == sourceId })?.currency
                        } else {
                            return account.currency
                        }
                    } else if account.isDeposit, let sourceId = sourceAccountId {
                        return accountsViewModel.accounts.first(where: { $0.id == sourceId })?.currency
                    } else {
                        return account.currency
                    }
                }
                
                if let sourceCurrency = sourceCurrency, selectedCurrency != sourceCurrency {
                    guard let converted = await CurrencyConverter.convert(
                        amount: amount,
                        from: selectedCurrency,
                        to: sourceCurrency
                    ) else {
                        await MainActor.run {
                            errorMessage = "Ошибка конвертации валюты. Проверьте подключение к интернету."
                            showingError = true
                            HapticManager.error()
                        }
                        return
                    }
                    convertedAmount = converted
                }
                
                // Предзагружаем курсы для конвертации targetAmount при создании перевода
                if let targetAccountId = selectedTargetAccountId {
                    let targetAccountCurrency: String? = await MainActor.run {
                        accountsViewModel.accounts.first(where: { $0.id == targetAccountId })?.currency
                    }

                    if let targetCurrency = targetAccountCurrency {
                        let currenciesToLoad = Set([selectedCurrency, account.currency, targetCurrency])

                        var allRatesLoaded = true
                        for currency in currenciesToLoad {
                            // Загружаем курс для каждой валюты (если еще не загружен)
                            let rate = await CurrencyConverter.getExchangeRate(for: currency)
                            if rate == nil && currency != "KZT" {
                                allRatesLoaded = false
                            }
                        }

                        // Проверяем, что все необходимые курсы валют доступны
                        if !allRatesLoaded {
                            await MainActor.run {
                                errorMessage = "Не удалось загрузить курсы валют. Проверьте подключение к интернету и попробуйте снова."
                                showingError = true
                                HapticManager.error()
                            }
                            return
                        }

                        // Проверяем конвертацию для всех пар валют (если разные)
                        if selectedCurrency != account.currency {
                            let sourceConversion = await CurrencyConverter.convert(
                                amount: amount,
                                from: selectedCurrency,
                                to: account.currency
                            )
                            if sourceConversion == nil {
                                await MainActor.run {
                                    errorMessage = "Не удалось конвертировать валюту для счета-источника. Проверьте подключение к интернету."
                                    showingError = true
                                    HapticManager.error()
                                }
                                return
                            }
                        }

                        if selectedCurrency != targetCurrency {
                            let targetConversion = await CurrencyConverter.convert(
                                amount: amount,
                                from: selectedCurrency,
                                to: targetCurrency
                            )
                            if targetConversion == nil {
                                await MainActor.run {
                                    errorMessage = "Не удалось конвертировать валюту для счета-получателя. Проверьте подключение к интернету."
                                    showingError = true
                                    HapticManager.error()
                                }
                                return
                            }
                        }

                        if account.currency != targetCurrency {
                            let crossConversion = await CurrencyConverter.convert(
                                amount: amount,
                                from: account.currency,
                                to: targetCurrency
                            )
                            if crossConversion == nil {
                                await MainActor.run {
                                    errorMessage = "Не удалось конвертировать валюту между счетами. Проверьте подключение к интернету."
                                    showingError = true
                                    HapticManager.error()
                                }
                                return
                            }
                        }
                    }
                }
            }
            
            // Предвычисляем targetAmount для переводов (в async контексте)
            var precomputedTargetAmount: Double? = nil
            if selectedAction != .income, let targetAccountId = selectedTargetAccountId {
                let targetAcc = await MainActor.run {
                    accountsViewModel.accounts.first(where: { $0.id == targetAccountId })
                }
                let resolvedTargetCurrency = targetAcc?.currency ?? selectedCurrency
                if selectedCurrency != resolvedTargetCurrency {
                    precomputedTargetAmount = await CurrencyConverter.convert(
                        amount: amount,
                        from: selectedCurrency,
                        to: resolvedTargetCurrency
                    )
                } else {
                    precomputedTargetAmount = amount
                }
            }

            // Все валидации и создание транзакции выполняем на MainActor
            await MainActor.run {
                if selectedAction == .income {
                    // Пополнение счета
                    guard let category = selectedCategory, !incomeCategories.isEmpty else {
                        errorMessage = String(localized: "transactionForm.selectCategoryIncome")
                        showingError = true
                        HapticManager.warning()
                        return
                    }
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

                    // Phase 7.4: Use TransactionStore for add operation
                    Task {
                        do {
                            _ = try await transactionStore.add(transaction)
                            await MainActor.run {
                                HapticManager.success()
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                showingError = true
                                HapticManager.error()
                            }
                        }
                    }
                } else {
                    // Перевод между счетами
                    guard let targetAccountId = selectedTargetAccountId else {
                        errorMessage = headerForAccountSelection
                        showingError = true
                        HapticManager.warning()
                        return
                    }
                    
                    // Валидация: предотвращаем перевод самому себе
                    guard targetAccountId != account.id else {
                        errorMessage = String(localized: "transactionForm.cannotTransferToSame")
                        showingError = true
                        HapticManager.warning()
                        return
                    }
                    
                    // Проверяем существование счета получателя
                    guard accountsViewModel.accounts.contains(where: { $0.id == targetAccountId }) else {
                        errorMessage = String(localized: "transactionForm.accountNotFound")
                        showingError = true
                        HapticManager.error()
                        return
                    }
                    
                    // Определяем направление перевода для депозитов
                    let (sourceId, targetId): (String, String)
                    if account.isDeposit {
                        if let direction = transferDirection {
                            // Для депозитов используем transferDirection для определения направления
                            switch direction {
                            case .toDeposit:
                                // Пополнение: С выбранного счета НА депозит
                                sourceId = targetAccountId
                                targetId = account.id
                            case .fromDeposit:
                                // Вывод: С депозита НА выбранный счет
                                sourceId = account.id
                                targetId = targetAccountId
                            }
                        } else {
                            // Fallback: по умолчанию пополнение (для обратной совместимости)
                            sourceId = targetAccountId
                            targetId = account.id
                        }
                    } else {
                        // Для обычных счетов: перевод С текущего счета НА выбранный счет
                        sourceId = account.id
                        targetId = targetAccountId
                    }
                    
                    // Phase 7.4: Use TransactionStore for transfer operations
                    // For all transfers (deposits and regular accounts), use transactionStore.transfer()
                    Task {
                        do {
                            // Get target account currency
                            let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetId })
                            let targetCurrency = targetAccount?.currency ?? account.currency

                            try await transactionStore.transfer(
                                from: sourceId,
                                to: targetId,
                                amount: amount,
                                currency: selectedCurrency,
                                targetAmount: precomputedTargetAmount,
                                targetCurrency: targetCurrency,
                                date: dateFormatter.string(from: selectedDate),
                                description: finalDescription
                            )

                            await MainActor.run {
                                HapticManager.success()
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                errorMessage = error.localizedDescription
                                showingError = true
                                HapticManager.error()
                            }
                        }
                    }
                }
            }
        }
    }
}

// CategoryRadioButton is now replaced by CategoryChip

#Preview {
    let coordinator = AppCoordinator()
    AccountActionView(
        transactionsViewModel: coordinator.transactionsViewModel,
        accountsViewModel: coordinator.accountsViewModel,
        account: Account(name: "Main", currency: "USD", iconSource: nil, initialBalance: 1000)
    )
}
