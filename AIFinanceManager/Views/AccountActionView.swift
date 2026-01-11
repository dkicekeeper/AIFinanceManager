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
                    Text("Перевод").tag(ActionType.transfer)
                    Text("Пополнение").tag(ActionType.income)
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
                            LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
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
                                HStack(spacing: AppSpacing.md) {
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
                                Text(Formatting.currencySymbol(for: currency)).tag(currency)
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
            .sheet(isPresented: $showingAccountHistory) {
                NavigationView {
                    HistoryView(viewModel: viewModel, initialAccountId: account.id)
                        .environmentObject(timeFilterManager)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
            .alert("Ошибка", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: 4)
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
        
        let dateFormatter = DateFormatters.dateFormatter
        let transactionDate = dateFormatter.string(from: date)
        
        // Для переводов не устанавливаем дефолтное описание, если оно не заполнено
        let finalDescription = descriptionText.isEmpty ? (selectedAction == .income ? "Пополнение счета" : "") : descriptionText
        
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
                // Для перевода: конвертируем для источника (если нужно)
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
                
                // Для переводов: всегда загружаем курсы валют для всех участвующих валют
                // Это нужно для convertSync в recalculateAccountBalances() и HistoryView
                // Получаем информацию о целевом счете для предзагрузки курсов
                if let targetAccountId = selectedTargetAccountId {
                    let targetAccountCurrency: String? = await MainActor.run {
                        viewModel.accounts.first(where: { $0.id == targetAccountId })?.currency
                    }

                    if let targetCurrency = targetAccountCurrency {
                        // Предзагружаем курсы для всех валют, участвующих в переводе
                        // Это гарантирует, что курсы будут в кэше для convertSync
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
            
            // Все валидации и создание транзакции выполняем на MainActor
            await MainActor.run {
                if selectedAction == .income {
                    // Пополнение счета
                    guard let category = selectedCategory, !incomeCategories.isEmpty else {
                        errorMessage = "Выберите категорию дохода"
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
                    viewModel.addTransaction(transaction)
                    HapticManager.success()
                    dismiss()
                } else {
                    // Перевод между счетами
                    guard let targetAccountId = selectedTargetAccountId else {
                        errorMessage = "Выберите счет получателя"
                        showingError = true
                        HapticManager.warning()
                        return
                    }
                    
                    // Валидация: предотвращаем перевод самому себе
                    guard targetAccountId != account.id else {
                        errorMessage = "Нельзя перевести средства на тот же счет"
                        showingError = true
                        HapticManager.warning()
                        return
                    }
                    
                    // Проверяем существование счета получателя
                    guard viewModel.accounts.contains(where: { $0.id == targetAccountId }) else {
                        errorMessage = "Счет получателя не найден"
                        showingError = true
                        HapticManager.error()
                        return
                    }
                    
                    // TODO: Добавить поле targetConvertedAmount в модель Transaction для хранения конвертированной суммы получателя
                    // Конвертацию для получателя делаем в recalculateAccountBalances() на лету через convertSync
                    let transaction = Transaction(
                        id: "",
                        date: transactionDate,
                        description: finalDescription,
                        amount: amount,
                        currency: selectedCurrency,
                        convertedAmount: convertedAmount, // Конвертированная сумма для источника (в валюте источника)
                        type: .internalTransfer,
                        category: "Перевод",
                        subcategory: nil,
                        accountId: account.id,
                        targetAccountId: targetAccountId
                    )
                    viewModel.addTransaction(transaction)
                    
                    // После добавления транзакции пересчитываем балансы, чтобы применить конвертацию для получателя
                    viewModel.recalculateAccountBalances()
                    
                    HapticManager.success()
                    dismiss()
                }
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

    private var styleHelper: CategoryStyleHelper {
        CategoryStyleHelper(category: category, type: type, customCategories: viewModel.customCategories)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(isSelected ? styleHelper.coinColor : styleHelper.coinColor.opacity(0.5))
                    .frame(width: AppIconSize.coin, height: AppIconSize.coin)
                    .overlay(
                        Image(systemName: styleHelper.iconName)
                            .font(.title2)
                            .foregroundColor(styleHelper.iconColor)
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? styleHelper.coinBorderColor : Color.clear, lineWidth: 3)
                    )

                Text(category)
                    .font(AppTypography.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(category) category")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    AccountActionView(
        viewModel: TransactionsViewModel(),
        account: Account(name: "Main", balance: 1000, currency: "USD", bankLogo: .none)
    )
}
