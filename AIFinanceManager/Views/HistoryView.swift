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
    
    // Кеш для отфильтрованных транзакций
    @State private var cachedFilteredTransactions: [Transaction] = []
    @State private var cachedGroupedTransactions: [String: [Transaction]] = [:]
    @State private var lastFilterState: (String, String?, Set<String>?) = ("", nil, nil)

    // Индекс аккаунтов для O(1) lookup вместо O(n)
    @State private var accountsById: [String: Account] = [:]
    @State private var searchTask: Task<Void, Never>?
    
    init(viewModel: TransactionsViewModel, initialCategory: String? = nil, initialAccountId: String? = nil) {
        self.viewModel = viewModel
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Фильтры
            filterSection
            
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

            // Создаем индекс аккаунтов для быстрого поиска
            buildAccountsIndex()

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
            // Пересоздаем индекс при изменении аккаунтов
            buildAccountsIndex()
            updateCachedTransactions()
        }
        .onChange(of: viewModel.filteredTransactions) { _, _ in
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
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Фильтр по времени - отображаем текущий фильтр (не редактируемый здесь)
                HStack {
                    Image(systemName: "calendar")
                    Text(timeFilterManager.currentFilter.displayName)
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(20)
                
                // Фильтр по счетам - выпадающий список
                Menu {
                    Button(action: { selectedAccountFilter = nil }) {
                        HStack {
                            Text("Все счета")
                            Spacer()
                            if selectedAccountFilter == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    ForEach(viewModel.accounts) { account in
                        Button(action: { selectedAccountFilter = account.id }) {
                            HStack(spacing: 8) {
                                account.bankLogo.image(size: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.subheadline)
                                    Text(Formatting.formatCurrency(account.balance, currency: account.currency))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedAccountFilter == account.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if let selectedAccount = viewModel.accounts.first(where: { $0.id == selectedAccountFilter }) {
                            selectedAccount.bankLogo.image(size: 16)
                        }
                        Text(selectedAccountFilter == nil ? "Все счета" : (viewModel.accounts.first(where: { $0.id == selectedAccountFilter })?.name ?? "Все счета"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(20)
                }
                
                // Фильтр по категориям
                Button(action: {
                    showingCategoryFilter = true
                }) {
                    HStack(spacing: 8) {
                        // Показываем иконку категории, если выбрана одна категория
                        categoryFilterIcon
                        Text(categoryFilterText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(viewModel.selectedCategories != nil ? Color.blue.opacity(0.2) : Color(.systemGray5))
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }
    
    private var transactionsList: some View {
        let grouped = cachedGroupedTransactions.isEmpty ? groupedTransactions : cachedGroupedTransactions
        
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
        
        // Сортируем ключи: будущие даты вверху (по возрастанию), затем Сегодня, Вчера, затем прошлые (по убыванию)
        let sortedKeys: [String] = {
            let keys = Array(grouped.keys)
            let calendar = Calendar.current
            let dateFormatter = DateFormatters.dateFormatter
            let today = Date()
            let todayStart = calendar.startOfDay(for: today)
            
            // Разделяем ключи на категории
            let todayKey = keys.first { $0 == "Сегодня" }
            let yesterdayKey = keys.first { $0 == "Вчера" }
            let otherKeys = keys.filter { $0 != "Сегодня" && $0 != "Вчера" }
            
            // Для остальных ключей находим дату первой транзакции в группе
            // Для recurring транзакций берем первую recurring, для обычных - первую обычную
            let keysWithDates: [(key: String, date: Date, isRecurring: Bool)] = otherKeys.compactMap { key in
                guard let transactionsInGroup = grouped[key] else { return nil }
                
                // Находим первую recurring транзакцию, если есть
                if let recurringTransaction = transactionsInGroup.first(where: { $0.recurringSeriesId != nil }),
                   let date = dateFormatter.date(from: recurringTransaction.date) {
                    return (key: key, date: date, isRecurring: true)
                }
                
                // Иначе берем первую обычную транзакцию
                if let firstTransaction = transactionsInGroup.first,
                   let date = dateFormatter.date(from: firstTransaction.date) {
                    return (key: key, date: date, isRecurring: false)
                }
                
                return nil
            }
            
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            
            // Разделяем на будущие и прошлые
            let futureKeys = keysWithDates.filter { $0.date > todayStart }
                .sorted { key1, key2 in
                    // Recurring транзакции сортируем по убыванию (ближайшие вверху) - 12 января, затем 11 января
                    if key1.isRecurring && key2.isRecurring {
                        return key1.date > key2.date
                    }
                    // Обычные транзакции также по убыванию для будущих дат (ближайшие вверху)
                    if !key1.isRecurring && !key2.isRecurring {
                        return key1.date > key2.date
                    }
                    // Recurring всегда перед обычными в будущих датах
                    return key1.isRecurring && !key2.isRecurring
                }
                .map { $0.key }
            
            // Разделяем прошлые даты на recurring и обычные (исключая "Вчера")
            let pastRecurringKeys = keysWithDates.filter { $0.date < yesterdayStart && $0.isRecurring }
                .sorted { $0.date < $1.date } // Recurring прошлые по возрастанию (старые вверху)
                .map { $0.key }
            
            let pastRegularKeys = keysWithDates.filter { $0.date < yesterdayStart && !$0.isRecurring }
                .sorted { $0.date > $1.date } // Обычные прошлые по убыванию (новые вверху)
                .map { $0.key }
            
            var result: [String] = []
            // Сначала будущие даты (recurring и обычные уже отсортированы)
            result.append(contentsOf: futureKeys)
            // Затем "Сегодня"
            if let today = todayKey {
                result.append(today)
            }
            // Затем "Вчера"
            if let yesterday = yesterdayKey {
                result.append(yesterday)
            }
            // Затем прошлые recurring (по возрастанию - старые вверху)
            result.append(contentsOf: pastRecurringKeys)
            // Затем прошлые обычные (по убыванию - новые вверху)
            result.append(contentsOf: pastRegularKeys)
            return result
        }()
        
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
                    // Скроллим к "Сегодня" при появлении, если есть, иначе к первой секции
                    let scrollTarget = sortedKeys.first { $0 == "Сегодня" } ?? sortedKeys.first
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
    
    private var filteredTransactions: [Transaction] {
        // Используем глобальный фильтр по времени из TimeFilterManager и фильтр по категориям
        var transactions = viewModel.transactionsFilteredByTimeAndCategory(timeFilterManager)
        
        // Фильтр по счету
        if let accountId = selectedAccountFilter {
            transactions = transactions.filter { $0.accountId == accountId || $0.targetAccountId == accountId }
        }
        
        // Фильтр по поиску (используем дебаунсированный текст)
        if !debouncedSearchText.isEmpty {
            let searchLower = debouncedSearchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let searchNumber = Double(debouncedSearchText.replacingOccurrences(of: ",", with: "."))
            
            transactions = transactions.filter { transaction in
                // Поиск по категории
                if transaction.category.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по подкатегориям
                let linkedSubcategories = viewModel.getSubcategoriesForTransaction(transaction.id)
                if linkedSubcategories.contains(where: { $0.name.lowercased().contains(searchLower) }) {
                    return true
                }
                
                // Поиск по описанию
                if transaction.description.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по счету (используем индекс для O(1) вместо O(n))
                if let accountId = transaction.accountId,
                   let account = accountsById[accountId],
                   account.name.lowercased().contains(searchLower) {
                    return true
                }

                if let targetAccountId = transaction.targetAccountId,
                   let targetAccount = accountsById[targetAccountId],
                   targetAccount.name.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по сумме (как строка, так и число)
                let amountString = String(format: "%.2f", transaction.amount)
                if amountString.contains(debouncedSearchText) || amountString.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по числовому значению суммы
                if let searchNum = searchNumber, abs(transaction.amount - searchNum) < 0.01 {
                    return true
                }
                
                // Поиск по сумме с валютой
                let currency = viewModel.appSettings.baseCurrency
                let formattedAmount = Formatting.formatCurrency(transaction.amount, currency: currency).lowercased()
                if formattedAmount.contains(searchLower) {
                    return true
                }
                
                return false
            }
        }
        
        return transactions
    }
    
    private var groupedTransactions: [String: [Transaction]] {
        let transactions = filteredTransactions
        var grouped: [String: [Transaction]] = [:]
        
        let calendar = Calendar.current
        let dateFormatter = DateFormatters.dateFormatter
        let displayDateFormatter = DateFormatters.displayDateFormatter
        let displayDateWithYearFormatter = DateFormatters.displayDateWithYearFormatter
        let currentYear = calendar.component(.year, from: Date())
        
        // Разделяем на recurring и обычные транзакции для разной сортировки
        var recurringTransactions: [Transaction] = []
        var regularTransactions: [Transaction] = []
        
        for transaction in transactions {
            if transaction.recurringSeriesId != nil {
                recurringTransactions.append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }
        
        // Recurring транзакции сортируем по возрастанию (ближайшие вверху)
        recurringTransactions.sort { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 < date2
        }
        
        // Обычные транзакции сортируем по убыванию (новые вверху)
        regularTransactions.sort { tx1, tx2 in
            if tx1.createdAt != tx2.createdAt {
                return tx1.createdAt > tx2.createdAt
            }
            return tx1.id > tx2.id
        }
        
        // Объединяем: сначала recurring, затем обычные
        let allTransactions = recurringTransactions + regularTransactions
        
        for transaction in allTransactions {
            guard let date = dateFormatter.date(from: transaction.date) else { continue }
            
            // Все транзакции, включая будущие recurring, группируются по дате
            // Recurring транзакции должны быть в своей дате повторения, а не в "Сегодня"
            let dateKey: String
            let today = calendar.startOfDay(for: Date())
            let transactionDay = calendar.startOfDay(for: date)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let transactionYear = calendar.component(.year, from: date)
            
            // Сравниваем только даты (без времени) для правильной группировки
            if transactionDay == today {
                // Транзакция сегодня - показываем в блоке "Сегодня"
                dateKey = "Сегодня"
            } else if transactionDay == yesterday {
                // Транзакция вчера - показываем в блоке "Вчера"
                dateKey = "Вчера"
            } else {
                // Транзакция в другой день (прошлая или будущая) - показываем дату
                // Если год не текущий - показываем год
                if transactionYear != currentYear {
                    dateKey = displayDateWithYearFormatter.string(from: date)
                } else {
                    dateKey = displayDateFormatter.string(from: date)
                }
            }
            
            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(transaction)
        }
        
        // Сортируем транзакции внутри каждого дня
        for key in grouped.keys {
            let today = calendar.startOfDay(for: Date())
            
            grouped[key]?.sort { tx1, tx2 in
                // Recurring транзакции сортируем по-разному в зависимости от даты
                let isRecurring1 = tx1.recurringSeriesId != nil
                let isRecurring2 = tx2.recurringSeriesId != nil
                
                if isRecurring1 && isRecurring2 {
                    guard let date1 = dateFormatter.date(from: tx1.date),
                          let date2 = dateFormatter.date(from: tx2.date) else {
                        return false
                    }
                    // Для будущих дат - по убыванию (ближайшие вверху: 12 января > 11 января)
                    // Для прошлых дат - по возрастанию (старые вверху: 8 января < 9 января)
                    if date1 > today && date2 > today {
                        // Обе даты в будущем - по убыванию
                        return date1 > date2
                    } else if date1 <= today && date2 <= today {
                        // Обе даты в прошлом - по возрастанию
                        return date1 < date2
                    } else {
                        // Одна в прошлом, одна в будущем - будущая всегда выше
                        return date1 > today && date2 <= today
                    }
                }
                
                // Обычные транзакции сортируем по убыванию (новые вверху)
                if !isRecurring1 && !isRecurring2 {
                    if tx1.createdAt != tx2.createdAt {
                        return tx1.createdAt > tx2.createdAt
                    }
                    return tx1.id > tx2.id
                }
                
                // Recurring всегда перед обычными
                return isRecurring1 && !isRecurring2
            }
        }
        
        return grouped
    }
    
    // Построение индекса аккаунтов для O(1) lookup
    private func buildAccountsIndex() {
        accountsById = Dictionary(uniqueKeysWithValues: viewModel.accounts.map { ($0.id, $0) })
    }

    // Обновление кешированных транзакций
    private func updateCachedTransactions() {
        PerformanceProfiler.start("HistoryView.updateCachedTransactions")
        let currentState = (timeFilterManager.currentFilter.displayName, selectedAccountFilter, viewModel.selectedCategories)

        // Всегда обновляем кеш, так как транзакции могли измениться
        lastFilterState = currentState
        cachedGroupedTransactions = groupedTransactions
        cachedFilteredTransactions = filteredTransactions
        PerformanceProfiler.end("HistoryView.updateCachedTransactions")
    }
    
    private var categoryFilterText: String {
        guard let selectedCategories = viewModel.selectedCategories else {
            return "Все категории"
        }
        if selectedCategories.count == 1 {
            return selectedCategories.first ?? "Все категории"
        }
        return "\(selectedCategories.count) категорий"
    }
    
    @ViewBuilder
    private var categoryFilterIcon: some View {
        if let selectedCategories = viewModel.selectedCategories,
           selectedCategories.count == 1,
           let category = selectedCategories.first {
            let isIncome: Bool = {
                if let customCategory = viewModel.customCategories.first(where: { $0.name == category }) {
                    return customCategory.type == .income
                } else {
                    return viewModel.incomeCategories.contains(category)
                }
            }()
            let categoryType: TransactionType = isIncome ? .income : .expense
            let iconName = CategoryEmoji.iconName(for: category, type: categoryType, customCategories: viewModel.customCategories)
            let iconColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: viewModel.customCategories)
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(isIncome ? Color.green : iconColor)
        }
    }
    
    private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
        let currency = viewModel.appSettings.baseCurrency
        let dayExpenses = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
        
        return HStack {
            Text(dateKey)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            if dayExpenses > 0 {
                Text("-" + Formatting.formatCurrency(dayExpenses, currency: currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
            }
        }
        .textCase(nil)
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
        HStack(spacing: 12) {
            // Иконка категории
            ZStack {
                Circle()
                    .fill(transaction.type == .internalTransfer ? Color.blue.opacity(0.2) : styleHelper.lightBackgroundColor)
                    .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                    .overlay(
                        Image(systemName: styleHelper.iconName)
                            .font(.system(size: AppIconSize.md))
                            .foregroundColor(transaction.type == .internalTransfer ? Color.blue : styleHelper.primaryColor)
                    )
                
                // Иконка повторения в правом нижнем углу
                if transaction.recurringSeriesId != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .padding(4)
                        .background(Color.white)
                        .clipShape(Circle())
                        .offset(x: 14, y: 14)
                }
            }
            
            // Информация
            VStack(alignment: .leading, spacing: 4) {
                // Название категории
                Text(transaction.category)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                // Подкатегории (если есть) - показываем через запятую
                let linkedSubcategories = viewModel?.getSubcategoriesForTransaction(transaction.id) ?? []
                if !linkedSubcategories.isEmpty {
                    Text(linkedSubcategories.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Для переводов показываем откуда → куда с логотипами счетов
                if transaction.type == .internalTransfer {
                    HStack(spacing: 6) {
                        if let sourceId = transaction.accountId,
                           let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                            HStack(spacing: 4) {
                                sourceAccount.bankLogo.image(size: 14)
                                Text(sourceAccount.name)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let targetId = transaction.targetAccountId,
                           let targetAccount = accounts.first(where: { $0.id == targetId }) {
                            HStack(spacing: 4) {
                                targetAccount.bankLogo.image(size: 14)
                                Text(targetAccount.name)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    // Счет (для не-переводов)
                    if let accountId = transaction.accountId,
                       let account = accounts.first(where: { $0.id == accountId }) {
                        HStack(spacing: 4) {
                            account.bankLogo.image(size: 14)
                            Text(account.name)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Описание (если есть)
                if !transaction.description.isEmpty {
                    Text(transaction.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Сумма
            VStack(alignment: .trailing, spacing: 2) {
                if transaction.type == .internalTransfer {
                    // Для переводов показываем две суммы с разными цветами и знаками
                    transferAmountView
                } else {
                    Text(amountText)
                        .font(.body)
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
            
            // Если есть счет получателя и валюта отличается от источника - показываем обе суммы
            if let target = targetAccount {
                let targetCurrency = target.currency
                
                // Если валюты источника и получателя одинаковые - показываем только сумму источника
                if sourceCurrency == targetCurrency {
                    Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                } else {
                    // Валюты разные - показываем обе суммы
                    Text("-\(Formatting.formatCurrency(sourceAmount, currency: sourceCurrency))")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    
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
                    
                    Text("+\(Formatting.formatCurrency(targetAmount, currency: targetCurrency))")
                        .font(.body)
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
                .font(.body)
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
