//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @EnvironmentObject var timeFilterManager: TimeFilterManager
    @State private var selectedAccountFilter: String? = nil // nil = все счета
    @State private var searchText = ""
    @State private var debouncedSearchText = "" // Дебаунсированный поиск
    @State private var showingCategoryFilter = false
    @State private var isSearchActive = false
    let initialCategory: String? // Категория для предустановленного фильтра (из лонгтапа)
    let initialAccountId: String? // Счет для предустановленного фильтра
    
    // Кеш для отфильтрованных и сгруппированных транзакций
    @State private var cachedGroupedTransactions: [String: [Transaction]] = [:]
    @State private var cachedSortedKeys: [String] = []
    @State private var searchTask: Task<Void, Never>?
    
    init(viewModel: TransactionsViewModel, initialCategory: String? = nil, initialAccountId: String? = nil) {
        self.viewModel = viewModel
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Фильтры
            HistoryFilterSection(
                viewModel: viewModel,
                selectedAccountFilter: $selectedAccountFilter,
                showingCategoryFilter: $showingCategoryFilter
            )
            
            // Список транзакций
            transactionsList
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: "Search by amount, category, or description")
        .task {
            // Устанавливаем фильтр по категории до onAppear, чтобы гарантировать применение
            if let category = initialCategory {
                viewModel.selectedCategories = [category]
            } else {
                viewModel.selectedCategories = nil
            }
        }
        .onAppear {
            PerformanceProfiler.start("HistoryView.onAppear")

            // Устанавливаем фильтр по счету при появлении
            if let accountId = initialAccountId, selectedAccountFilter != accountId {
                selectedAccountFilter = accountId
            }

            debouncedSearchText = searchText
            updateCachedTransactions()
            PerformanceProfiler.end("HistoryView.onAppear")
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: selectedAccountFilter) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Отменяем предыдущий поиск
            searchTask?.cancel()

            // Дебаунсируем поиск - обновляем через 300ms после последнего ввода
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                guard !Task.isCancelled else { return }

                if searchText == newValue { // Проверяем, что значение не изменилось за это время
                    await MainActor.run {
                        debouncedSearchText = newValue
                        updateCachedTransactions()
                    }
                }
            }
        }
        .onChange(of: viewModel.accounts) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: viewModel.selectedCategories) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: viewModel.allTransactions) { _, _ in
            // Обновляем кеш при изменении транзакций (например, после редактирования)
            updateCachedTransactions()
        }
        .onDisappear {
            // Сбрасываем фильтры при выходе из истории
            selectedAccountFilter = nil
            viewModel.selectedCategories = nil
        }
        .sheet(isPresented: $showingCategoryFilter) {
            CategoryFilterView(viewModel: viewModel)
        }
    }
    
    
    private var transactionsList: some View {
        let grouped = cachedGroupedTransactions
        let sortedKeys = cachedSortedKeys
        
        if grouped.isEmpty {
            // Определяем контекстное сообщение в зависимости от активных фильтров
            let emptyMessage: String = {
                if !debouncedSearchText.isEmpty {
                    return "Попробуйте изменить поисковый запрос"
                } else if selectedAccountFilter != nil || viewModel.selectedCategories != nil {
                    return "Попробуйте изменить фильтры или добавьте новую операцию"
                } else {
                    return "Начните добавлять операции, чтобы отслеживать ваши финансы"
                }
            }()

            return AnyView(
                EmptyStateView(
                    icon: !debouncedSearchText.isEmpty ? "magnifyingglass" : "doc.text",
                    title: !debouncedSearchText.isEmpty ? "Ничего не найдено" : "Нет операций",
                    description: emptyMessage
                )
                .padding(.top, AppSpacing.xxxl)
            )
        }
        
        return AnyView(
            ScrollViewReader { proxy in
                List {
                    ForEach(sortedKeys, id: \.self) { dateKey in
                        Section(header: dateHeader(for: dateKey, transactions: grouped[dateKey] ?? [])) {
                            ForEach(grouped[dateKey] ?? []) { transaction in
                                TransactionCard(
                                    transaction: transaction,
                                    currency: viewModel.appSettings.baseCurrency,
                                    customCategories: viewModel.customCategories,
                                    accounts: viewModel.accounts,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .id(dateKey)
                    }
                }
                .listStyle(PlainListStyle())
                .onAppear {
                    // Скроллим к первой не-будущей секции (Сегодня, Вчера, или первая прошлая)
                    // sortedKeys содержит: futureKeys, затем "Сегодня", "Вчера", затем прошлые
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let dateFormatter = DateFormatters.dateFormatter
                    
                    // Находим индекс первой не-будущей секции
                    let scrollTarget: String? = {
                        // Сначала проверяем "Сегодня"
                        if sortedKeys.contains("Сегодня") {
                            return "Сегодня"
                        }
                        // Затем проверяем "Вчера"
                        if sortedKeys.contains("Вчера") {
                            return "Вчера"
                        }
                        // Ищем первую прошлую секцию (не будущую)
                        for key in sortedKeys {
                            if key == "Сегодня" || key == "Вчера" {
                                continue
                            }
                            // Проверяем, является ли эта секция будущей
                            if let transactions = grouped[key],
                               let firstTransaction = transactions.first,
                               let date = dateFormatter.date(from: firstTransaction.date) {
                                let transactionDay = calendar.startOfDay(for: date)
                                if transactionDay <= today {
                                    return key
                                }
                            }
                        }
                        // Если ничего не нашли, возвращаем первую секцию
                        return sortedKeys.first
                    }()
                    
                    if let target = scrollTarget {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
            }
        )
    }
    
    // Обновление кешированных транзакций
    private func updateCachedTransactions() {
        PerformanceProfiler.start("HistoryView.updateCachedTransactions")
        
        // Фильтруем транзакции
        let filtered = viewModel.filterTransactionsForHistory(
            timeFilterManager: timeFilterManager,
            accountId: selectedAccountFilter,
            searchText: debouncedSearchText
        )
        
        // Группируем и сортируем
        let result = viewModel.groupAndSortTransactionsByDate(filtered)
        cachedGroupedTransactions = result.grouped
        cachedSortedKeys = result.sortedKeys
        
        PerformanceProfiler.end("HistoryView.updateCachedTransactions")
    }
    
    
    private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
        let currency = viewModel.appSettings.baseCurrency
        let baseCurrency = viewModel.appSettings.baseCurrency
        
        // Конвертируем все расходы в базовую валюту перед суммированием
        let dayExpenses = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { total, transaction in
                let amountInBaseCurrency: Double
                if transaction.currency == baseCurrency {
                    amountInBaseCurrency = transaction.amount
                } else {
                    if let converted = CurrencyConverter.convertSync(
                        amount: transaction.amount,
                        from: transaction.currency,
                        to: baseCurrency
                    ) {
                        amountInBaseCurrency = converted
                    } else {
                        // Если конвертация невозможна, используем convertedAmount или amount
                        amountInBaseCurrency = transaction.convertedAmount ?? transaction.amount
                    }
                }
                return total + amountInBaseCurrency
            }
        
        return DateSectionHeader(
            dateKey: dateKey,
            dayExpenses: dayExpenses,
            currency: currency
        )
    }
}

struct TransactionCard: View {
    let transaction: Transaction
    let currency: String
    let customCategories: [CustomCategory]
    let accounts: [Account]
    let viewModel: TransactionsViewModel?

    @State private var showingEditDialog = false
    @State private var showingDeleteDialog = false
    @State private var showingStopRecurringConfirmation = false
    @State private var showingEditModal = false

    // Кеш для style helper - вычисляется один раз
    private var styleHelper: CategoryStyleHelper {
        CategoryStyleHelper(category: transaction.category, type: transaction.type, customCategories: customCategories)
    }

    init(transaction: Transaction, currency: String, customCategories: [CustomCategory], accounts: [Account], viewModel: TransactionsViewModel? = nil) {
        self.transaction = transaction
        self.currency = currency
        self.customCategories = customCategories
        self.accounts = accounts
        self.viewModel = viewModel
    }
    
    private var isFutureDate: Bool {
        let dateFormatter = DateFormatters.dateFormatter
        guard let transactionDate = dateFormatter.date(from: transaction.date) else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        // Транзакция с будущей датой (дата > today)
        return transactionDate > today
    }
    
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Transaction icon
            TransactionIconView(transaction: transaction, styleHelper: styleHelper)
            
            // Transaction info
            TransactionInfoView(
                transaction: transaction,
                accounts: accounts,
                linkedSubcategories: viewModel?.getSubcategoriesForTransaction(transaction.id) ?? []
            )
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                if transaction.type == .internalTransfer {
                    transferAmountView
                } else {
                    Text(amountText)
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(amountColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .opacity(isFutureDate ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Swipe left for options")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Удаление - для recurring транзакций просто удаляем операцию без диалога
            Button(role: .destructive) {
                HapticManager.warning()
                if let viewModel = viewModel {
                    viewModel.deleteTransaction(transaction)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete transaction")

            // Управление recurring (если есть)
            if transaction.recurringSeriesId != nil {
                Button {
                    showingStopRecurringConfirmation = true
                } label: {
                    Label("Recurring", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
                .accessibilityLabel("Stop recurring transaction")
            }
        }
        .alert("Прекратить повторение?", isPresented: $showingStopRecurringConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Прекратить повторение", role: .destructive) {
                HapticManager.warning()
                if let viewModel = viewModel, let seriesId = transaction.recurringSeriesId {
                    viewModel.stopRecurringSeries(seriesId)
                    // После остановки серии нужно удалить будущие транзакции и перегенерировать список
                    let dateFormatter = DateFormatters.dateFormatter
                    guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }
                    let today = Calendar.current.startOfDay(for: Date())
                    
                    // Удаляем все будущие транзакции этой серии (начиная со следующего дня после текущей транзакции)
                    let futureOccurrences = viewModel.recurringOccurrences.filter { occurrence in
                        guard occurrence.seriesId == seriesId,
                              let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                            return false
                        }
                        // Удаляем только будущие транзакции (после даты текущей транзакции)
                        return occurrenceDate > transactionDate && occurrenceDate > today
                    }
                    
                    for occurrence in futureOccurrences {
                        viewModel.allTransactions.removeAll { $0.id == occurrence.transactionId }
                        viewModel.recurringOccurrences.removeAll { $0.id == occurrence.id }
                    }
                    
                    viewModel.recalculateAccountBalances()
                    viewModel.saveToStorage()
                }
            }
        } message: {
            Text("Это прекратит повторение операции. Все будущие транзакции будут удалены.")
        }
        .onTapGesture {
            showingEditModal = true
        }
        .sheet(isPresented: $showingEditModal) {
            if let viewModel = viewModel {
                EditTransactionView(
                    transaction: transaction,
                    viewModel: viewModel,
                    accounts: accounts,
                    customCategories: customCategories
                )
            }
        }
    }
    
    
    private var amountText: String {
        let prefix: String
        switch transaction.type {
        case .income:
            prefix = "+"
        case .expense:
            prefix = "-"
        case .internalTransfer:
            prefix = "" // Для переводов без префикса
        case .depositTopUp, .depositInterestAccrual:
            prefix = "+"
        case .depositWithdrawal:
            prefix = "-"
        }
        let mainAmount = Formatting.formatCurrency(transaction.amount, currency: transaction.currency)
        
        // Для переводов: показываем суммы для обоих счетов друг под другом
        if transaction.type == .internalTransfer {
            var lines: [String] = []
            
            // Получаем информацию о счетах
            var sourceAccount: Account? = nil
            var targetAccount: Account? = nil
            
            if let sourceId = transaction.accountId {
                sourceAccount = accounts.first(where: { $0.id == sourceId })
            }
            if let targetId = transaction.targetAccountId {
                targetAccount = accounts.first(where: { $0.id == targetId })
            }
            
            // Если счетов нет, показываем только основную сумму
            guard let source = sourceAccount else {
                return mainAmount
            }
            
            // Сумма для источника
            var sourceAmount: Double = transaction.amount
            var sourceCurrency: String = transaction.currency
            
            sourceCurrency = source.currency
            if transaction.currency == source.currency {
                // Валюты совпадают - используем сумму как есть
                sourceAmount = transaction.amount
            } else if let convertedAmount = transaction.convertedAmount {
                // Есть конвертированная сумма для источника
                sourceAmount = convertedAmount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: source.currency
            ) {
                // Конвертируем на лету
                sourceAmount = converted
            }
            
            // Если есть счет получателя и валюта отличается от источника - показываем обе суммы
            if let target = targetAccount {
                let targetCurrency = target.currency
                
                // Если валюты источника и получателя одинаковые - показываем только сумму источника
                if sourceCurrency == targetCurrency {
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                } else {
                    // Валюты разные - показываем обе суммы
                    lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
                    
                    var targetAmount: Double = transaction.amount
                    if transaction.currency == targetCurrency {
                        // Валюты совпадают - используем сумму как есть
                        targetAmount = transaction.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: transaction.amount,
                        from: transaction.currency,
                        to: targetCurrency
                    ) {
                        // Валюты разные - конвертируем на лету через кэш
                        targetAmount = converted
                    }
                    lines.append(Formatting.formatCurrency(targetAmount, currency: targetCurrency))
                }
            } else {
                // Если счета получателя нет, показываем только сумму источника
                lines.append(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))
            }
            
            // Объединяем все строки через \n (суммы друг под другом, без скобок)
            return lines.isEmpty ? mainAmount : lines.joined(separator: "\n")
        }
        
        // Для доходов и расходов: если есть конвертированная сумма и она отличается от основной, показываем обе
        if let convertedAmount = transaction.convertedAmount,
           let accountId = transaction.accountId,
           let account = accounts.first(where: { $0.id == accountId }),
           transaction.currency != account.currency {
            let convertedText = Formatting.formatCurrency(convertedAmount, currency: account.currency)
            return "\(prefix)\(mainAmount)\n(\(convertedText))"
        }
        
        return prefix + mainAmount
    }
    
    private var accessibilityText: String {
        let typeText = transaction.type == .income ? "Income" : transaction.type == .expense ? "Expense" : "Transfer"
        let amountText = Formatting.formatCurrency(transaction.amount, currency: transaction.currency)
        var text = "\(typeText), \(transaction.category), \(amountText)"

        if transaction.type == .internalTransfer {
            // Для переводов: указываем источник и получателя
            if let sourceId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                text += ", from \(sourceAccount.name)"
            }
            if let targetId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetId }) {
                text += ", to \(targetAccount.name)"
            }
        } else {
            // Для доходов и расходов: указываем счет
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                text += ", from \(account.name)"
            }
        }

        if !transaction.description.isEmpty {
            text += ", \(transaction.description)"
        }

        if transaction.recurringSeriesId != nil {
            text += ", recurring transaction"
        }

        return text
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income:
            return .green
        case .expense:
            return .red
        case .internalTransfer:
            return .blue // Синий цвет для переводов для консистентности с иконкой
        case .depositTopUp, .depositInterestAccrual:
            return .green
        case .depositWithdrawal:
            return .red
        }
    }
    
    @ViewBuilder
    private var transferAmountView: some View {
        // Получаем информацию о счетах
        let sourceAccount: Account? = transaction.accountId.flatMap { sourceId in
            accounts.first(where: { $0.id == sourceId })
        }
        let targetAccount: Account? = transaction.targetAccountId.flatMap { targetId in
            accounts.first(where: { $0.id == targetId })
        }
        
        if let source = sourceAccount {
            // Вычисляем сумму для источника
            let sourceCurrency = source.currency
            let sourceAmount: Double = {
                if transaction.currency == sourceCurrency {
                    return transaction.amount
                } else if let convertedAmount = transaction.convertedAmount {
                    return convertedAmount
                } else if let converted = CurrencyConverter.convertSync(
                    amount: transaction.amount,
                    from: transaction.currency,
                    to: sourceCurrency
                ) {
                    return converted
                } else {
                    return transaction.amount
                }
            }()
            
            // Если есть счет получателя - показываем обе суммы
            if let target = targetAccount {
                let targetCurrency = target.currency
                
                // Вычисляем сумму для получателя
                let targetAmount: Double = {
                    if transaction.currency == targetCurrency {
                        return transaction.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: transaction.amount,
                        from: transaction.currency,
                        to: targetCurrency
                    ) {
                        return converted
                    } else {
                        return transaction.amount
                    }
                }()
                
                // Всегда показываем обе суммы (источника с минусом, получателя с плюсом)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    
                    Text("+\(Formatting.formatCurrency(targetAmount, currency: targetCurrency))")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            } else {
                // Если счета получателя нет, показываем только сумму источника
                Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }
        } else {
            // Если счета источника нет, показываем основную сумму
            Text(amountText)
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(amountColor)
        }
    }
}

// View для фильтрации по категориям
struct CategoryFilterView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedExpenseCategories: Set<String> = []
    @State private var selectedIncomeCategories: Set<String> = []
    
    var body: some View {
        NavigationView {
            Form {
                // Опция "Все категории"
                Section {
                    HStack {
                        Text("Все категории")
                            .fontWeight(.medium)
                        Spacer()
                        if viewModel.selectedCategories == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedExpenseCategories.removeAll()
                        selectedIncomeCategories.removeAll()
                        viewModel.selectedCategories = nil
                    }
                }
                
                // Категории расходов
                Section(header: Text("Расходы")) {
                    if viewModel.expenseCategories.isEmpty {
                        Text("Нет категорий расходов")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.expenseCategories, id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                if selectedExpenseCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedExpenseCategories.contains(category) {
                                    selectedExpenseCategories.remove(category)
                                } else {
                                    selectedExpenseCategories.insert(category)
                                }
                            }
                        }
                    }
                }
                
                // Категории доходов
                Section(header: Text("Доходы")) {
                    if viewModel.incomeCategories.isEmpty {
                        Text("Нет категорий доходов")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.incomeCategories, id: \.self) { category in
                            HStack {
                                Text(category)
                                Spacer()
                                if selectedIncomeCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIncomeCategories.contains(category) {
                                    selectedIncomeCategories.remove(category)
                                } else {
                                    selectedIncomeCategories.insert(category)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Фильтр по категориям")
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
                        applyFilter()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                // Загружаем текущий фильтр
                if let currentFilter = viewModel.selectedCategories {
                    selectedExpenseCategories = Set(viewModel.expenseCategories.filter { currentFilter.contains($0) })
                    selectedIncomeCategories = Set(viewModel.incomeCategories.filter { currentFilter.contains($0) })
                }
            }
        }
    }
    
    private func applyFilter() {
        let allSelected = selectedExpenseCategories.union(selectedIncomeCategories)
        if allSelected.isEmpty {
            // Если ничего не выбрано, показываем все категории
            viewModel.selectedCategories = nil
        } else {
            viewModel.selectedCategories = allSelected
        }
    }
}

#Preview {
    NavigationView {
        HistoryView(viewModel: TransactionsViewModel())
    }
}
