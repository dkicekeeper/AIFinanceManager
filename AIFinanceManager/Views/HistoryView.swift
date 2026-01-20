//
//  HistoryView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var transactionsViewModel: TransactionsViewModel
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
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
    
    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        initialCategory: String? = nil,
        initialAccountId: String? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Фильтры
            HistoryFilterSection(
                transactionsViewModel: transactionsViewModel,
                accountsViewModel: accountsViewModel,
                categoriesViewModel: categoriesViewModel,
                selectedAccountFilter: $selectedAccountFilter,
                showingCategoryFilter: $showingCategoryFilter
            )
            
            // Список транзакций
            transactionsList
        }
        .navigationTitle(String(localized: "navigation.history"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, isPresented: $isSearchActive, prompt: String(localized: "search.placeholder"))
        .task {
            // Устанавливаем фильтр по категории до onAppear, чтобы гарантировать применение
            if let category = initialCategory {
                transactionsViewModel.selectedCategories = [category]
            } else {
                transactionsViewModel.selectedCategories = nil
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
        .onChange(of: transactionsViewModel.accounts) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: transactionsViewModel.selectedCategories) { _, _ in
            updateCachedTransactions()
        }
        .onChange(of: transactionsViewModel.allTransactions) { _, _ in
            // Обновляем кеш при изменении транзакций (например, после редактирования)
            updateCachedTransactions()
        }
        .onDisappear {
            // Сбрасываем фильтры при выходе из истории
            selectedAccountFilter = nil
            transactionsViewModel.selectedCategories = nil
        }
        .sheet(isPresented: $showingCategoryFilter) {
            CategoryFilterView(viewModel: transactionsViewModel)
        }
    }
    
    
    private var transactionsList: some View {
        let grouped = cachedGroupedTransactions
        let sortedKeys = cachedSortedKeys
        
        if grouped.isEmpty {
            // Определяем контекстное сообщение в зависимости от активных фильтров
            let emptyMessage: String = {
                if !debouncedSearchText.isEmpty {
                    return String(localized: "emptyState.tryDifferentSearch")
                } else if selectedAccountFilter != nil || transactionsViewModel.selectedCategories != nil {
                    return String(localized: "emptyState.tryDifferentFilters")
                } else {
                    return String(localized: "emptyState.startTracking")
                }
            }()

            return AnyView(
                EmptyStateView(
                    icon: !debouncedSearchText.isEmpty ? "magnifyingglass" : "doc.text",
                    title: !debouncedSearchText.isEmpty ? String(localized: "emptyState.searchNoResults") : String(localized: "emptyState.noTransactions"),
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
                                    currency: transactionsViewModel.appSettings.baseCurrency,
                                    customCategories: categoriesViewModel.customCategories,
                                    accounts: accountsViewModel.accounts,
                                    viewModel: transactionsViewModel,
                                    categoriesViewModel: categoriesViewModel
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
        let filtered = transactionsViewModel.filterTransactionsForHistory(
            timeFilterManager: timeFilterManager,
            accountId: selectedAccountFilter,
            searchText: debouncedSearchText
        )
        
        // Группируем и сортируем
        let result = transactionsViewModel.groupAndSortTransactionsByDate(filtered)
        cachedGroupedTransactions = result.grouped
        cachedSortedKeys = result.sortedKeys
        
        PerformanceProfiler.end("HistoryView.updateCachedTransactions")
    }
    
    
    private func dateHeader(for dateKey: String, transactions: [Transaction]) -> some View {
        let currency = transactionsViewModel.appSettings.baseCurrency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        
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
            .navigationTitle(String(localized: "navigation.categoryFilter"))
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
    let coordinator = AppCoordinator()
    NavigationView {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
}
