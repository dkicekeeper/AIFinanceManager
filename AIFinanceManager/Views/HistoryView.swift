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
    
    // Локализованные ключи для дат (используются ViewModel для группировки)
    // TODO: Исправить ViewModel для использования локализованных ключей
    private var todayKey: String {
        String(localized: "date.today")
    }
    
    private var yesterdayKey: String {
        String(localized: "date.yesterday")
    }
    
    // Кешируем baseCurrency для оптимизации
    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }
    
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
        transactionsList
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    // Фильтры
                    HistoryFilterSection(
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: accountsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        selectedAccountFilter: $selectedAccountFilter,
                        showingCategoryFilter: $showingCategoryFilter
                    )
                }
                .background(Color(.clear))
            }
            .navigationTitle(String(localized: "navigation.history"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(.clear), for: .navigationBar)
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
            HapticManager.selection()
            updateCachedTransactions()
        }
        .onChange(of: selectedAccountFilter) { _, _ in
            HapticManager.selection()
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
            HapticManager.selection()
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
                                    currency: baseCurrency,
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
                .task {
                    // Скроллим к первой не-будущей секции (Сегодня, Вчера, или первая прошлая)
                    // sortedKeys содержит: futureKeys, затем локализованные "Сегодня"/"Вчера", затем прошлые
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                    
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let dateFormatter = DateFormatters.dateFormatter
                    
                    // Находим индекс первой не-будущей секции
                    let scrollTarget: String? = {
                        // Сначала проверяем "Сегодня" (используем локализованный ключ)
                        if sortedKeys.contains(todayKey) {
                            return todayKey
                        }
                        // Затем проверяем "Вчера" (используем локализованный ключ)
                        if sortedKeys.contains(yesterdayKey) {
                            return yesterdayKey
                        }
                        // Ищем первую прошлую секцию (не будущую)
                        for key in sortedKeys {
                            if key == todayKey || key == yesterdayKey {
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
                        withAnimation {
                            proxy.scrollTo(target, anchor: .top)
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
            currency: baseCurrency
        )
    }
}

// MARK: - Previews

#Preview("History View") {
    let coordinator = AppCoordinator()
    NavigationView {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
        .environmentObject(TimeFilterManager())
    }
}

#Preview("History View - Empty") {
    let coordinator = AppCoordinator()
    coordinator.transactionsViewModel.allTransactions = []
    
    return NavigationView {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel
        )
        .environmentObject(TimeFilterManager())
    }
}

#Preview("History View - With Filters") {
    let coordinator = AppCoordinator()
    coordinator.transactionsViewModel.selectedCategories = ["Food", "Transport"]
    
    return NavigationView {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            initialCategory: "Food",
            initialAccountId: coordinator.accountsViewModel.accounts.first?.id
        )
        .environmentObject(TimeFilterManager())
    }
}
