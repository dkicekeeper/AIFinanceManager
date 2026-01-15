//
//  TransactionsViewModel.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TransactionsViewModel: ObservableObject {
    @Published var allTransactions: [Transaction] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var accounts: [Account] = []
    @Published var customCategories: [CustomCategory] = []
    @Published var recurringSeries: [RecurringSeries] = []
    @Published var recurringOccurrences: [RecurringOccurrence] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    @Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []
    @Published var selectedCategories: Set<String>? = nil // nil = все категории, Set = выбранные категории
    
    // TimeFilterManager передается через EnvironmentObject, не хранится здесь
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currencyConversionWarning: String? = nil // Предупреждение о проблемах с конвертацией валют
    @Published var appSettings: AppSettings = AppSettings.load() // Настройки приложения

    // Храним начальные балансы счетов (баланс при создании/редактировании)
    private var initialAccountBalances: [String: Double] = [:]
    
    // Кеш для summary
    private var cachedSummary: Summary?
    private var summaryCacheInvalidated = true

    // Кеш для categoryExpenses
    private var cachedCategoryExpenses: [String: CategoryExpense]?
    private var categoryExpensesCacheInvalidated = true

    // Метод для инвалидации кешей (используется при смене базовой валюты)
    func invalidateCaches() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
    }
    
    // MARK: - Repository
    
    let repository: DataRepositoryProtocol
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        PerformanceProfiler.start("ViewModel.init")
        loadFromStorage()
        // Генерируем recurring транзакции асинхронно, чтобы не блокировать UI при запуске
        // Используем Task с небольшой задержкой, чтобы UI успел отобразиться
        Task { @MainActor in
            // Небольшая задержка, чтобы UI успел загрузиться
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
            PerformanceProfiler.start("generateRecurringTransactions")
            generateRecurringTransactions()
            PerformanceProfiler.end("generateRecurringTransactions")
            
            // Note: Deposit reconciliation should be handled by DepositsViewModel
            // This is now deprecated and should be removed after full migration
        }
        PerformanceProfiler.end("ViewModel.init")
    }
    
    // Используем кешированный DateFormatter из утилит
    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }
    
    // Фильтрация по времени теперь происходит через TimeFilterManager
    // Этот метод фильтрует только по категориям и применяет правила
    var filteredTransactions: [Transaction] {
        var transactions = applyRules(to: allTransactions)
        
        // Фильтр по категориям
        if let selectedCategories = selectedCategories {
            transactions = transactions.filter { transaction in
                selectedCategories.contains(transaction.category)
            }
        }
        
        return filterRecurringTransactions(transactions)
    }
    
    // Метод для фильтрации транзакций с учетом TimeFilterManager (без фильтра по категориям)
    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        // Используем allTransactions с применением правил, но БЕЗ фильтра по категориям
        let transactions = applyRules(to: allTransactions)
        return transactions.filter { transaction in
            guard let transactionDate = Self.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= range.start && transactionDate < range.end
        }
    }
    
    // Метод для фильтрации транзакций с учетом TimeFilterManager И фильтра по категориям (для истории)
    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        let range = timeFilterManager.currentFilter.dateRange()
        var transactions = applyRules(to: allTransactions)
        
        // Фильтр по категориям
        if let selectedCategories = selectedCategories {
            transactions = transactions.filter { transaction in
                selectedCategories.contains(transaction.category)
            }
        }
        
        // Разделяем на recurring и обычные транзакции
        var recurringTransactions: [Transaction] = []
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]
        
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                // Группируем recurring транзакции по сериям
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                // Обычные транзакции фильтруем по времени
                guard let transactionDate = Self.dateFormatter.date(from: transaction.date) else {
                    continue
                }
                if transactionDate >= range.start && transactionDate < range.end {
                    regularTransactions.append(transaction)
                }
            }
        }
        
        // Для каждой recurring серии показываем только одну транзакцию - следующую по дате
        let dateFormatter = Self.dateFormatter
        
        for series in recurringSeries where series.isActive {
            guard let seriesTransactions = recurringTransactionsBySeries[series.id] else {
                continue
            }
            
            // Находим следующую транзакцию (ближайшую по дате, включая сегодня)
            let nextTransaction = seriesTransactions
                .compactMap { transaction -> (Transaction, Date)? in
                    guard let date = dateFormatter.date(from: transaction.date) else {
                        return nil
                    }
                    return (transaction, date)
                }
                .min(by: { $0.1 < $1.1 }) // Ближайшая по дате
                .map { $0.0 }
            
            if let nextTransaction = nextTransaction {
                recurringTransactions.append(nextTransaction)
            }
        }
        
        // Объединяем: сначала recurring, затем обычные
        return recurringTransactions + regularTransactions
    }
    
    // MARK: - History View Filtering and Grouping
    
    /// Фильтрует транзакции для HistoryView с учетом всех фильтров (время, категории, счет, поиск)
    func filterTransactionsForHistory(
        timeFilterManager: TimeFilterManager,
        accountId: String?,
        searchText: String
    ) -> [Transaction] {
        // Базовая фильтрация по времени и категориям
        var transactions = transactionsFilteredByTimeAndCategory(timeFilterManager)
        
        // Фильтр по счету
        if let accountId = accountId {
            transactions = transactions.filter { $0.accountId == accountId || $0.targetAccountId == accountId }
        }
        
        // Фильтр по поиску
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let searchNumber = Double(searchText.replacingOccurrences(of: ",", with: "."))
            
            // Создаем индекс аккаунтов для O(1) lookup
            let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            
            transactions = transactions.filter { transaction in
                // Поиск по категории
                if transaction.category.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по подкатегориям
                let linkedSubcategories = getSubcategoriesForTransaction(transaction.id)
                if linkedSubcategories.contains(where: { $0.name.lowercased().contains(searchLower) }) {
                    return true
                }
                
                // Поиск по описанию
                if transaction.description.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по счету
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
                if amountString.contains(searchText) || amountString.lowercased().contains(searchLower) {
                    return true
                }
                
                // Поиск по числовому значению суммы
                if let searchNum = searchNumber, abs(transaction.amount - searchNum) < 0.01 {
                    return true
                }
                
                // Поиск по сумме с валютой
                let currency = appSettings.baseCurrency
                let formattedAmount = Formatting.formatCurrency(transaction.amount, currency: currency).lowercased()
                if formattedAmount.contains(searchLower) {
                    return true
                }
                
                return false
            }
        }
        
        return transactions
    }
    
    /// Группирует транзакции по датам и возвращает словарь с группированными транзакциями и отсортированными ключами
    func groupAndSortTransactionsByDate(_ transactions: [Transaction]) -> (grouped: [String: [Transaction]], sortedKeys: [String]) {
        var grouped: [String: [Transaction]] = [:]
        
        let calendar = Calendar.current
        let dateFormatter = Self.dateFormatter
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
            
            let dateKey: String
            let today = calendar.startOfDay(for: Date())
            let transactionDay = calendar.startOfDay(for: date)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let transactionYear = calendar.component(.year, from: date)
            
            if transactionDay == today {
                dateKey = "Сегодня"
            } else if transactionDay == yesterday {
                dateKey = "Вчера"
            } else {
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
                let isRecurring1 = tx1.recurringSeriesId != nil
                let isRecurring2 = tx2.recurringSeriesId != nil
                
                if isRecurring1 && isRecurring2 {
                    guard let date1 = dateFormatter.date(from: tx1.date),
                          let date2 = dateFormatter.date(from: tx2.date) else {
                        return false
                    }
                    if date1 > today && date2 > today {
                        return date1 > date2
                    } else if date1 <= today && date2 <= today {
                        return date1 < date2
                    } else {
                        return date1 > today && date2 <= today
                    }
                }
                
                if !isRecurring1 && !isRecurring2 {
                    if tx1.createdAt != tx2.createdAt {
                        return tx1.createdAt > tx2.createdAt
                    }
                    return tx1.id > tx2.id
                }
                
                return isRecurring1 && !isRecurring2
            }
        }
        
        // Сортируем ключи: будущие даты вверху, затем Сегодня, Вчера, затем прошлые
        let keys = Array(grouped.keys)
        let todayKey = keys.first { $0 == "Сегодня" }
        let yesterdayKey = keys.first { $0 == "Вчера" }
        let otherKeys = keys.filter { $0 != "Сегодня" && $0 != "Вчера" }
        
        let keysWithDates: [(key: String, date: Date, isRecurring: Bool)] = otherKeys.compactMap { key in
            guard let transactionsInGroup = grouped[key] else { return nil }
            
            if let recurringTransaction = transactionsInGroup.first(where: { $0.recurringSeriesId != nil }),
               let date = dateFormatter.date(from: recurringTransaction.date) {
                return (key: key, date: date, isRecurring: true)
            }
            
            if let firstTransaction = transactionsInGroup.first,
               let date = dateFormatter.date(from: firstTransaction.date) {
                return (key: key, date: date, isRecurring: false)
            }
            
            return nil
        }
        
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        
        let futureKeys = keysWithDates.filter { $0.date > calendar.startOfDay(for: Date()) }
            .sorted { key1, key2 in
                if key1.isRecurring && key2.isRecurring {
                    return key1.date > key2.date
                }
                if !key1.isRecurring && !key2.isRecurring {
                    return key1.date > key2.date
                }
                return key1.isRecurring && !key2.isRecurring
            }
            .map { $0.key }
        
        let pastRecurringKeys = keysWithDates.filter { $0.date < yesterdayStart && $0.isRecurring }
            .sorted { $0.date < $1.date }
            .map { $0.key }
        
        let pastRegularKeys = keysWithDates.filter { $0.date < yesterdayStart && !$0.isRecurring }
            .sorted { $0.date > $1.date }
            .map { $0.key }
        
        var sortedKeys: [String] = []
        sortedKeys.append(contentsOf: futureKeys)
        if let today = todayKey {
            sortedKeys.append(today)
        }
        if let yesterday = yesterdayKey {
            sortedKeys.append(yesterday)
        }
        sortedKeys.append(contentsOf: pastRecurringKeys)
        sortedKeys.append(contentsOf: pastRegularKeys)
        
        return (grouped, sortedKeys)
    }
    
    // Фильтрует recurring транзакции: показывает только следующую для каждой серии
    private func filterRecurringTransactions(_ transactions: [Transaction]) -> [Transaction] {
        // Используем кэшированный DateFormatter
        let dateFormatter = Self.dateFormatter
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var result: [Transaction] = []
        var recurringSeriesShown: Set<String> = []
        
        // Оптимизация: разделяем обычные и recurring транзакции за один проход
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]
        
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }
        
        result.append(contentsOf: regularTransactions)
        
        // Для каждой активной recurring серии находим следующую транзакцию
        for series in recurringSeries where series.isActive {
            if recurringSeriesShown.contains(series.id) {
                continue
            }
            
            guard let seriesTransactions = recurringTransactionsBySeries[series.id] else {
                continue
            }
            
            // Находим следующую транзакцию (сегодня или в будущем)
            // Сортируем только если нужно
            let nextTransaction = seriesTransactions
                .compactMap { transaction -> (Transaction, Date)? in
                    guard let date = dateFormatter.date(from: transaction.date) else {
                        return nil
                    }
                    return (transaction, date)
                }
                .filter { $0.1 >= today }
                .min(by: { $0.1 < $1.1 })
                .map { $0.0 }
            
            if let nextTransaction = nextTransaction {
                result.append(nextTransaction)
                recurringSeriesShown.insert(series.id)
            }
        }
        
        // Сортируем результат по дате (новые сверху)
        return result.sorted { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 > date2
        }
    }
    
    // Summary теперь требует TimeFilterManager для фильтрации по времени
    func summary(timeFilterManager: TimeFilterManager) -> Summary {
        // Используем кеш если он валиден (но только если фильтр не изменился)
        // Пока отключаем кеш, так как фильтр может меняться
        PerformanceProfiler.start("summary.calculation")
        
        let filtered = transactionsFilteredByTime(timeFilterManager)
        // Исключаем невыполненные recurring операции из расходов
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        let range = timeFilterManager.currentFilter.dateRange()
        
        // Оптимизация: один проход вместо множественных фильтров
        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        
        for transaction in filtered {
            // Конвертируем все суммы в базовую валюту
            let baseCurrency = appSettings.baseCurrency
            let amountInBaseCurrency: Double
            if transaction.currency == baseCurrency {
                // Если транзакция уже в базовой валюте, используем сумму напрямую
                amountInBaseCurrency = transaction.amount
            } else {
                // Конвертируем в базовую валюту через синхронный метод (курсы должны быть в кэше)
                if let converted = CurrencyConverter.convertSync(
                    amount: transaction.amount,
                    from: transaction.currency,
                    to: baseCurrency
                ) {
                    amountInBaseCurrency = converted
                } else {
                    // Если конвертация невозможна, используем convertedAmount или amount
                    amountInBaseCurrency = transaction.convertedAmount ?? transaction.amount
                    print("⚠️ Не удалось конвертировать транзакцию \(transaction.id) в \(baseCurrency) для summary")
                }
            }

            // Проверяем, является ли транзакция будущей (дата > today)
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                continue
            }

            let isFutureDate = transactionDate > today

            // Учитываем в расходах только транзакции с датой <= today (выполненные)
            if !isFutureDate {
                switch transaction.type {
                case .income:
                    totalIncome += amountInBaseCurrency
                case .expense:
                    totalExpenses += amountInBaseCurrency
                case .internalTransfer:
                    totalInternal += amountInBaseCurrency
                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    // Транзакции депозита не учитываются в общей статистике
                    break
                }
            }
        }
        
        // Рассчитываем plannedAmount на основе активных recurring серий и диапазона фильтра
        // Это позволяет корректно показывать планируемые расходы даже если транзакции еще не сгенерированы
        var plannedAmount: Double = 0
        
        // Если фильтр относится к будущему (range.end > today), рассчитываем планируемые расходы
        if range.end > today {
            let calendar = Calendar.current
            
            // Рассчитываем диапазон для планируемых транзакций: от today до конца фильтра
            // Ограничиваем максимальный горизонт планирования до 2 лет для производительности
            let maxHorizon = calendar.date(byAdding: .year, value: 2, to: today) ?? range.end
            let planningEnd = min(range.end, maxHorizon)
            
            for series in recurringSeries where series.isActive {
                guard let seriesStartDate = dateFormatter.date(from: series.startDate) else { continue }
                
                // Определяем начало планирования для этой серии
                var firstRecurringDate: Date
                
                if seriesStartDate <= today {
                    // Серия уже началась - первая будущая транзакция будет на следующей дате по частоте
                    guard let nextDate = {
                        switch series.frequency {
                        case .daily:
                            return calendar.date(byAdding: .day, value: 1, to: today)
                        case .weekly:
                            return calendar.date(byAdding: .day, value: 7, to: today)
                        case .monthly:
                            return calendar.date(byAdding: .month, value: 1, to: today)
                        case .yearly:
                            return calendar.date(byAdding: .year, value: 1, to: today)
                        }
                    }() else {
                        continue
                    }
                    firstRecurringDate = nextDate
                } else {
                    // Серия начинается в будущем - первая транзакция на startDate
                    firstRecurringDate = seriesStartDate
                }
                
                // Если первая транзакция после конца фильтра, пропускаем
                if firstRecurringDate >= planningEnd {
                    continue
                }
                
                // Рассчитываем количество транзакций в диапазоне для данной частоты
                let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue

                // Конвертируем сумму recurring серии в базовую валюту
                let baseCurrency = appSettings.baseCurrency
                let amountInBaseCurrency: Double
                if series.currency == baseCurrency {
                    amountInBaseCurrency = amountDouble
                } else {
                    if let converted = CurrencyConverter.convertSync(
                        amount: amountDouble,
                        from: series.currency,
                        to: baseCurrency
                    ) {
                        amountInBaseCurrency = converted
                    } else {
                        amountInBaseCurrency = amountDouble
                        print("⚠️ Не удалось конвертировать recurring series \(series.id) в \(baseCurrency) для plannedAmount")
                    }
                }

                var currentDate = firstRecurringDate
                var transactionCount = 0
                
                // Считаем количество транзакций в диапазоне планирования
                while currentDate < planningEnd {
                    transactionCount += 1
                    
                    // Переходим к следующей дате по частоте
                    guard let nextDate = {
                        switch series.frequency {
                        case .daily:
                            return calendar.date(byAdding: .day, value: 1, to: currentDate)
                        case .weekly:
                            return calendar.date(byAdding: .day, value: 7, to: currentDate)
                        case .monthly:
                            return calendar.date(byAdding: .month, value: 1, to: currentDate)
                        case .yearly:
                            return calendar.date(byAdding: .year, value: 1, to: currentDate)
                        }
                    }() else {
                        break
                    }
                    
                    // Проверяем, не вышли ли за пределы диапазона
                    if nextDate >= planningEnd {
                        break
                    }
                    
                    currentDate = nextDate
                }

                // Добавляем планируемую сумму: количество транзакций × сумма транзакции (в базовой валюте)
                plannedAmount += Double(transactionCount) * amountInBaseCurrency
            }
            
            // Учитываем обычные будущие транзакции (expense и income)
            // Проходим по всем транзакциям и находим те, которые:
            // 1. Имеют будущую дату (date > today)
            // 2. Попадают в диапазон фильтра (range.start <= date <= range.end)
            // 3. Не являются recurring (recurringSeriesId == nil)
            for transaction in filtered {
                // Пропускаем recurring транзакции - они уже учтены выше
                if transaction.recurringSeriesId != nil {
                    continue
                }
                
                // Проверяем, является ли транзакция будущей и попадает ли в диапазон фильтра
                guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                    continue
                }
                
                // Транзакция должна быть в будущем (date > today) и попадать в диапазон фильтра
                // range.start уже учитывается в filtered, но проверяем range.end для безопасности
                if transactionDate > today && transactionDate >= range.start && transactionDate <= range.end {
                    // Конвертируем сумму в базовую валюту (используем ту же логику, что и для выполненных транзакций)
                    let baseCurrency = appSettings.baseCurrency
                    let amountInBaseCurrency: Double
                    if transaction.currency == baseCurrency {
                        // Если транзакция уже в базовой валюте, используем сумму напрямую
                        amountInBaseCurrency = transaction.amount
                    } else {
                        // Конвертируем в базовую валюту через синхронный метод (курсы должны быть в кэше)
                        if let converted = CurrencyConverter.convertSync(
                            amount: transaction.amount,
                            from: transaction.currency,
                            to: baseCurrency
                        ) {
                            amountInBaseCurrency = converted
                        } else {
                            // Если конвертация невозможна (курсы не загружены в кэш), используем amount
                            // Это может привести к неточности, но лучше чем ничего
                            // Примечание: convertedAmount - это сумма в валюте счета, а не базовой валюты,
                            // поэтому его нельзя использовать напрямую
                            amountInBaseCurrency = transaction.amount
                            print("⚠️ Не удалось конвертировать будущую транзакцию \(transaction.id) в \(baseCurrency) для plannedAmount. Используется сумма в валюте транзакции: \(transaction.amount) \(transaction.currency)")
                        }
                    }
                    
                    // Учитываем только expense транзакции (расходы) в планах
                    // Income (доходы) и internalTransfer (переводы) не учитываются
                    if transaction.type == .expense {
                        plannedAmount += amountInBaseCurrency
                    }
                }
            }
        }

        // Используем базовую валюту из настроек для summary
        let dates = allTransactions.map { $0.date }.sorted()

        let result = Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: appSettings.baseCurrency, // Базовая валюта из настроек
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            plannedAmount: plannedAmount
        )
        
        // Сохраняем в кеш
        cachedSummary = result
        summaryCacheInvalidated = false
        
        PerformanceProfiler.end("summary.calculation")
        return result
    }
    
    // CategoryExpenses теперь требует TimeFilterManager для фильтрации по времени
    func categoryExpenses(timeFilterManager: TimeFilterManager) -> [String: CategoryExpense] {
        // Используем кеш если он валиден (но только если фильтр не изменился)
        // Пока отключаем кеш, так как фильтр может меняться
        
        let filtered = transactionsFilteredByTime(timeFilterManager).filter { $0.type == .expense }
        var result: [String: CategoryExpense] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        
        for transaction in filtered {
            // Исключаем транзакции с будущей датой из расходов
            guard let transactionDate = dateFormatter.date(from: transaction.date),
                  transactionDate <= today else {
                continue
            }

            let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category

            // Конвертируем все суммы в базовую валюту
            let baseCurrency = appSettings.baseCurrency
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
                    print("⚠️ Не удалось конвертировать транзакцию \(transaction.id) в \(baseCurrency) для categoryExpenses")
                }
            }

            // Безопасное обновление без force unwrap
            var expense = result[category] ?? CategoryExpense(total: 0, subcategories: [:])
            expense.total += amountInBaseCurrency

            if let subcategory = transaction.subcategory {
                expense.subcategories[subcategory, default: 0] += amountInBaseCurrency
            }

            result[category] = expense
        }
        
        // Сохраняем в кеш
        cachedCategoryExpenses = result
        categoryExpensesCacheInvalidated = false
        
        return result
    }
    
    func popularCategories(timeFilterManager: TimeFilterManager) -> [String] {
        let expenses = categoryExpenses(timeFilterManager: timeFilterManager)
        return Array(expenses.keys)
            .sorted { expenses[$0]?.total ?? 0 > expenses[$1]?.total ?? 0 }
    }
    
    var uniqueCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }
        return Array(categories).sorted()
    }
    
    // Получить все уникальные категории расходов
    var expenseCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .expense {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        return Array(categories).sorted()
    }
    
    // Получить все уникальные категории доходов
    var incomeCategories: [String] {
        var categories = Set<String>()
        for transaction in allTransactions where transaction.type == .income {
            categories.insert(transaction.category.isEmpty ? "Uncategorized" : transaction.category)
        }
        return Array(categories).sorted()
    }
    
    func addTransactions(_ newTransactions: [Transaction]) {
        // Сначала применяем правила и сопоставляем с существующими категориями
        let processedTransactions = newTransactions.map { transaction -> Transaction in
            // Форматируем описание: только название поставщика, с заглавной буквы
            let formattedDescription = formatMerchantName(transaction.description)
            
            // Сопоставляем категорию с существующими (case-insensitive)
            let matchedCategory = matchCategory(transaction.category, type: transaction.type)
            
            return Transaction(
                id: transaction.id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt // Сохраняем оригинальный createdAt
            )
        }
        
        let transactionsWithRules = applyRules(to: processedTransactions)
        
        // Remove duplicates
        let existingIDs = Set(allTransactions.map { $0.id })
        let uniqueNew = transactionsWithRules.filter { !existingIDs.contains($0.id) }
        
        if !uniqueNew.isEmpty {
            // Автоматически создаем категории для новых транзакций
            createCategoriesForTransactions(uniqueNew)

            // Оптимизированная вставка вместо полной сортировки
            insertTransactionsSorted(uniqueNew)
            invalidateCaches()
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    // Форматирует название поставщика: только название, с заглавной буквы
    private func formatMerchantName(_ description: String) -> String {
        // Убираем код авторизации и референс
        var cleaned = description
        
        // Удаляем паттерны типа "Референс: ..." или "Код авторизации: ..."
        let patterns = [
            "Референс:\\s*[A-Za-z0-9]+",
            "Код авторизации:\\s*[0-9]+",
            "Референс:",
            "Код авторизации:",
            "Reference:",
            "Authorization Code:"
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            if let regex = regex {
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        // Убираем лишние пробелы и форматируем: первая буква заглавная, остальные строчные
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Разбиваем на слова и форматируем каждое слово
        let words = cleaned.components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }
            .map { word -> String in
                // Если слово в верхнем регистре (например, "YANDEX.GO"), форматируем
                if word == word.uppercased() && word.count > 1 {
                    // Сохраняем точки и другие символы, но форматируем буквы
                    var result = ""
                    var isFirstChar = true
                    for char in word {
                        if char.isLetter {
                            result += isFirstChar ? char.uppercased() : char.lowercased()
                            isFirstChar = false
                        } else {
                            result += String(char)
                            // После точки или другого символа следующая буква должна быть заглавной
                            if char == "." || char == "-" {
                                isFirstChar = true
                            }
                        }
                    }
                    return result
                }
                // Для обычных слов используем capitalized
                return word.capitalized
            }
        
        return words.joined(separator: " ")
    }
    
    // Сопоставляет категорию с существующими (case-insensitive)
    private func matchCategory(_ categoryName: String, type: TransactionType) -> String {
        let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categoryName }
        
        // Ищем существующую категорию (case-insensitive)
        if let existing = customCategories.first(where: { category in
            category.name.caseInsensitiveCompare(trimmed) == .orderedSame &&
            category.type == type
        }) {
            return existing.name // Возвращаем точное название существующей категории
        }
        
        // Если не найдена, возвращаем исходное название (будет создана новая категория)
        return trimmed
    }
    
    // Создает категории для транзакций, если они не существуют
    private func createCategoriesForTransactions(_ transactions: [Transaction]) {
        for transaction in transactions {
            // Пропускаем internal transfers
            guard transaction.type != .internalTransfer else { continue }
            
            let categoryName = transaction.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !categoryName.isEmpty else { continue }
            
            // Проверяем, существует ли уже категория с таким именем (case-insensitive)
            let existingCategory = customCategories.first { category in
                category.name.caseInsensitiveCompare(categoryName) == .orderedSame &&
                category.type == transaction.type
            }
            
            if existingCategory == nil {
                // Создаем новую категорию
                let iconName = CategoryIcon.iconName(for: categoryName, type: transaction.type, customCategories: customCategories)
                let defaultColors: [String] = [
                    "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
                    "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
                    "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
                ]
                let color = defaultColors.randomElement() ?? "#3b82f6"
                
                let newCategory = CustomCategory(
                    name: categoryName,
                    iconName: iconName,
                    colorHex: color,
                    type: transaction.type
                )
                
                customCategories.append(newCategory)
                print("✅ Создана новая категория: \(categoryName) (\(transaction.type.rawValue))")
            }
        }
    }
    
    func addTransaction(_ transaction: Transaction) {
        // Форматируем описание и сопоставляем категорию
        let formattedDescription = formatMerchantName(transaction.description)
        let matchedCategory = matchCategory(transaction.category, type: transaction.type)
        
        let transactionWithID: Transaction
        if transaction.id.isEmpty {
            // Используем createdAt транзакции для генерации уникального ID
            let id = TransactionIDGenerator.generateID(
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                type: transaction.type,
                currency: transaction.currency,
                createdAt: transaction.createdAt
            )
            transactionWithID = Transaction(
                id: id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt // Сохраняем createdAt из переданной транзакции (если есть)
            )
        } else {
            transactionWithID = Transaction(
                id: transaction.id,
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: matchedCategory,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt // Сохраняем createdAt из переданной транзакции (если есть)
            )
        }
        
        let transactionsWithRules = applyRules(to: [transactionWithID])
        let existingIDs = Set(allTransactions.map { $0.id })
        
        if !existingIDs.contains(transactionWithID.id) {
            // Для internalTransfer с депозитами обновляем principalBalance
            if transactionWithID.type == .internalTransfer {
                if let sourceId = transactionWithID.accountId,
                   let targetId = transactionWithID.targetAccountId {
                    // Проверяем, нужно ли обновлять депозиты
                    let sourceIsDeposit = accounts.first(where: { $0.id == sourceId })?.isDeposit ?? false
                    let targetIsDeposit = accounts.first(where: { $0.id == targetId })?.isDeposit ?? false
                    
                    if sourceIsDeposit || targetIsDeposit {
                        // Обновляем балансы депозитов с конвертацией валют
                        updateDepositBalancesForTransfer(
                            transaction: transactionWithID,
                            sourceId: sourceId,
                            targetId: targetId
                        )
                    }
                }
            }
            
            // Создаем категорию, если нужно
            createCategoriesForTransactions(transactionsWithRules)

            // Оптимизированная вставка вместо полной сортировки
            insertTransactionsSorted(transactionsWithRules)
            invalidateCaches()
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    // Helper функция для обновления балансов депозитов при переводе
    private func updateDepositBalancesForTransfer(transaction: Transaction, sourceId: String, targetId: String) {
        guard let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = accounts.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        
        let sourceAccount = accounts[sourceIndex]
        let targetAccount = accounts[targetIndex]
        
        // Вычисляем сумму для источника в валюте источника
        let sourceAmount: Double = {
            if transaction.currency == sourceAccount.currency {
                return transaction.amount
            } else if let convertedAmount = transaction.convertedAmount, transaction.currency == sourceAccount.currency {
                return convertedAmount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: sourceAccount.currency
            ) {
                return converted
            } else {
                return transaction.amount
            }
        }()
        
        // Вычисляем сумму для получателя в валюте получателя
        let targetAmount: Double = {
            if transaction.currency == targetAccount.currency {
                return transaction.amount
            } else if let converted = CurrencyConverter.convertSync(
                amount: transaction.amount,
                from: transaction.currency,
                to: targetAccount.currency
            ) {
                return converted
            } else {
                return transaction.amount
            }
        }()
        
        // Обновляем источник (депозит)
        if var sourceDepositInfo = sourceAccount.depositInfo {
            let amountDecimal = Decimal(sourceAmount)
            // Сначала снимаем с накопленных процентов (если есть и капитализация выключена), затем с principal
            if !sourceDepositInfo.capitalizationEnabled && sourceDepositInfo.interestAccruedNotCapitalized > 0 {
                if amountDecimal <= sourceDepositInfo.interestAccruedNotCapitalized {
                    sourceDepositInfo.interestAccruedNotCapitalized -= amountDecimal
                } else {
                    let remaining = amountDecimal - sourceDepositInfo.interestAccruedNotCapitalized
                    sourceDepositInfo.interestAccruedNotCapitalized = 0
                    sourceDepositInfo.principalBalance -= remaining
                }
            } else {
                sourceDepositInfo.principalBalance -= amountDecimal
            }
            accounts[sourceIndex].depositInfo = sourceDepositInfo
            // Обновляем баланс счета на основе depositInfo
            var totalBalance: Decimal = sourceDepositInfo.principalBalance
            if !sourceDepositInfo.capitalizationEnabled {
                totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
            }
            accounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            // Для обычных счетов просто уменьшаем баланс
            accounts[sourceIndex].balance -= sourceAmount
        }
        
        // Обновляем получатель (депозит)
        if var targetDepositInfo = targetAccount.depositInfo {
            let amountDecimal = Decimal(targetAmount)
            targetDepositInfo.principalBalance += amountDecimal
            accounts[targetIndex].depositInfo = targetDepositInfo
            // Обновляем баланс счета на основе depositInfo
            var totalBalance: Decimal = targetDepositInfo.principalBalance
            if !targetDepositInfo.capitalizationEnabled {
                totalBalance += targetDepositInfo.interestAccruedNotCapitalized
            }
            accounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            // Для обычных счетов просто увеличиваем баланс
            accounts[targetIndex].balance += targetAmount
        }
    }
    
    func updateTransactionCategory(_ transactionId: String, category: String, subcategory: String?) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transactionId }) else {
            return
        }
        
        let transaction = allTransactions[index]
        
        // Create and save rule
        let newRule = CategoryRule(
            description: transaction.description,
            category: category,
            subcategory: subcategory
        )
        
        categoryRules.removeAll { $0.description.lowercased() == newRule.description.lowercased() }
        categoryRules.append(newRule)
        
        // Apply rule to all matching transactions
        for i in allTransactions.indices {
            if allTransactions[i].description.lowercased() == newRule.description.lowercased() {
                allTransactions[i] = Transaction(
                    id: allTransactions[i].id,
                    date: allTransactions[i].date,
                    description: allTransactions[i].description,
                    amount: allTransactions[i].amount,
                    currency: allTransactions[i].currency,
                    convertedAmount: allTransactions[i].convertedAmount,
                    type: allTransactions[i].type,
                    category: category,
                    subcategory: subcategory,
                    accountId: allTransactions[i].accountId,
                    targetAccountId: allTransactions[i].targetAccountId,
                    recurringSeriesId: allTransactions[i].recurringSeriesId,
                    recurringOccurrenceId: allTransactions[i].recurringOccurrenceId,
                    createdAt: allTransactions[i].createdAt // Сохраняем оригинальный createdAt
                )
            }
        }
        
        invalidateCaches()
        saveToStorage()
    }
    
    func clearHistory() {
        allTransactions = []
        categoryRules = []
        accounts = []
        saveToStorage()
    }
    
    // Полное обнуление всех данных приложения
    func resetAllData() {
        // Очищаем все массивы данных
        allTransactions = []
        categoryRules = []
        accounts = []
        customCategories = []
        recurringSeries = []
        recurringOccurrences = []
        subcategories = []
        categorySubcategoryLinks = []
        transactionSubcategoryLinks = []
        
        // Очищаем начальные балансы
        initialAccountBalances = [:]
        
        // Очищаем фильтры
        // dateFilter удален - теперь используется TimeFilterManager
        selectedCategories = nil
        
        // Очищаем кеши
        invalidateCaches()
        
        // Удаляем все данные через repository
        repository.clearAllData()
        
        print("✅ Все данные приложения обнулены")
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        // Удаляем транзакцию
        allTransactions.removeAll { $0.id == transaction.id }
        
        // Если это recurring occurrence, удаляем и его
        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }
        
        invalidateCaches()
        recalculateAccountBalances()
        saveToStorage()
    }
    
    func updateTransaction(_ transaction: Transaction) {
        guard let index = allTransactions.firstIndex(where: { $0.id == transaction.id }) else {
            return
        }
        allTransactions[index] = transaction
        invalidateCaches()
        recalculateAccountBalances()
        saveToStorage()
    }

    // MARK: - Custom Categories
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.addCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.addCategory instead")
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        invalidateCaches()
        saveToStorage()
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.updateCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.updateCategory instead")
    func updateCategory(_ category: CustomCategory) {
        guard let index = customCategories.firstIndex(where: { $0.id == category.id }) else {
            // Если категория не найдена, возможно это новая категория с существующим id
            // В этом случае добавляем её
            print("Warning: Category with id \(category.id) not found, adding as new")
            customCategories.append(category)
            saveToStorage()
            return
        }
        
        // Сохраняем старое название для обновления транзакций
        let oldCategory = customCategories[index]
        let oldName = oldCategory.name
        let newName = category.name
        
        // Обновляем категорию
        customCategories[index] = category
        
        // Обновляем все транзакции с этой категорией, если изменилось название
        if oldName != newName {
            for i in allTransactions.indices {
            if allTransactions[i].category == oldName {
                allTransactions[i] = Transaction(
                    id: allTransactions[i].id,
                    date: allTransactions[i].date,
                    description: allTransactions[i].description,
                    amount: allTransactions[i].amount,
                    currency: allTransactions[i].currency,
                        convertedAmount: allTransactions[i].convertedAmount,
                        type: allTransactions[i].type,
                        category: newName,
                        subcategory: allTransactions[i].subcategory,
                        accountId: allTransactions[i].accountId,
                        targetAccountId: allTransactions[i].targetAccountId,
                        recurringSeriesId: allTransactions[i].recurringSeriesId,
                        recurringOccurrenceId: allTransactions[i].recurringOccurrenceId,
                        createdAt: allTransactions[i].createdAt // Сохраняем оригинальный createdAt
                    )
                }
            }
            
            // Обновляем recurring series с этой категорией
            for i in recurringSeries.indices {
                if recurringSeries[i].category == oldName {
                    recurringSeries[i].category = newName
                }
            }
        }
        
        invalidateCaches()
        saveToStorage()
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.deleteCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.deleteCategory instead")
    func deleteCategory(_ category: CustomCategory, deleteTransactions: Bool = false) {
        if deleteTransactions {
            // Удаляем все операции с этой категорией
            allTransactions.removeAll { transaction in
                transaction.category == category.name && transaction.type == category.type
            }
            // Пересчитываем балансы счетов после удаления операций
            recalculateAccountBalances()
        } else {
            // Просто удаляем категорию, оставляя операции (они станут без категории или Uncategorized)
            // Можно опционально обновить категорию в транзакциях на "Uncategorized"
            for i in allTransactions.indices {
                if allTransactions[i].category == category.name && allTransactions[i].type == category.type {
                    allTransactions[i] = Transaction(
                        id: allTransactions[i].id,
                        date: allTransactions[i].date,
                        description: allTransactions[i].description,
                        amount: allTransactions[i].amount,
                        currency: allTransactions[i].currency,
                        convertedAmount: allTransactions[i].convertedAmount,
                        type: allTransactions[i].type,
                        category: "Uncategorized",
                        subcategory: allTransactions[i].subcategory,
                        accountId: allTransactions[i].accountId,
                        targetAccountId: allTransactions[i].targetAccountId,
                        recurringSeriesId: allTransactions[i].recurringSeriesId,
                        recurringOccurrenceId: allTransactions[i].recurringOccurrenceId,
                        createdAt: allTransactions[i].createdAt // Сохраняем оригинальный createdAt
                    )
                }
            }
        }
        
        // Удаляем связи категории с подкатегориями (используем ID категории до удаления)
        categorySubcategoryLinks.removeAll { $0.categoryId == category.id }
        
        // Обновляем recurring серии, если они используют эту категорию
        var seriesIdsToRemove: [String] = []
        if deleteTransactions {
            // Собираем ID серий для удаления
            seriesIdsToRemove = recurringSeries
                .filter { $0.category == category.name }
                .map { $0.id }
            
            // Удаляем recurring серии, если удаляем операции
            recurringSeries.removeAll { $0.category == category.name }
            
            // Удаляем все occurrences удаленных серий
            recurringOccurrences.removeAll { seriesIdsToRemove.contains($0.seriesId) }
        } else {
            // Обновляем категорию на "Uncategorized" в сериях
            for i in recurringSeries.indices {
                if recurringSeries[i].category == category.name {
                    recurringSeries[i].category = "Uncategorized"
                }
            }
        }
        
        // Удаляем категорию
        customCategories.removeAll { $0.id == category.id }
        invalidateCaches()
        saveToStorage()
    }
    
    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    // MARK: - Accounts

    /// ⚠️ DEPRECATED: Use AccountsViewModel.addAccount instead
    @available(*, deprecated, message: "Use AccountsViewModel.addAccount instead")
    func addAccount(name: String, balance: Double, currency: String, bankLogo: BankLogo = .none) {
        let account = Account(name: name, balance: balance, currency: currency, bankLogo: bankLogo)
        accounts.append(account)
        // Сохраняем начальный баланс
        initialAccountBalances[account.id] = balance
        recalculateAccountBalances()
        saveToStorage()
    }

    /// ⚠️ DEPRECATED: Use AccountsViewModel.updateAccount instead
    @available(*, deprecated, message: "Use AccountsViewModel.updateAccount instead")
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            // Обновляем начальный баланс при редактировании
            initialAccountBalances[account.id] = account.balance
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    /// ⚠️ DEPRECATED: Use AccountsViewModel.deleteAccount instead
    @available(*, deprecated, message: "Use AccountsViewModel.deleteAccount instead")
    func deleteAccount(_ account: Account) {
        // Удаляем все операции, связанные с этим счетом
        allTransactions.removeAll { transaction in
            transaction.accountId == account.id || transaction.targetAccountId == account.id
        }
        
        accounts.removeAll { $0.id == account.id }
        recalculateAccountBalances()
        saveToStorage()
    }

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        guard
            let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = accounts.firstIndex(where: { $0.id == targetId }),
            amount > 0
        else { return }

        let currency = accounts[sourceIndex].currency

        // Обновляем балансы и principalBalance для депозитов
        accounts[sourceIndex].balance -= amount
        
        // Если источник - депозит, уменьшаем principalBalance
        if var sourceDepositInfo = accounts[sourceIndex].depositInfo {
            let amountDecimal = Decimal(amount)
            // Сначала снимаем с накопленных процентов (если есть и капитализация выключена), затем с principal
            if !sourceDepositInfo.capitalizationEnabled && sourceDepositInfo.interestAccruedNotCapitalized > 0 {
                if amountDecimal <= sourceDepositInfo.interestAccruedNotCapitalized {
                    sourceDepositInfo.interestAccruedNotCapitalized -= amountDecimal
                } else {
                    let remaining = amountDecimal - sourceDepositInfo.interestAccruedNotCapitalized
                    sourceDepositInfo.interestAccruedNotCapitalized = 0
                    sourceDepositInfo.principalBalance -= remaining
                }
            } else {
                sourceDepositInfo.principalBalance -= amountDecimal
            }
            accounts[sourceIndex].depositInfo = sourceDepositInfo
            // Обновляем баланс счета на основе depositInfo
            var totalBalance: Decimal = sourceDepositInfo.principalBalance
            if !sourceDepositInfo.capitalizationEnabled {
                totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
            }
            accounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        }
        
        // Если получатель - депозит, нужно конвертировать валюту
        let targetAccount = accounts[targetIndex]
        let targetAmount: Double
        if currency == targetAccount.currency {
            targetAmount = amount
        } else if let converted = CurrencyConverter.convertSync(
            amount: amount,
            from: currency,
            to: targetAccount.currency
        ) {
            targetAmount = converted
        } else {
            // Если конвертация невозможна, используем исходную сумму (будет неточный баланс)
            print("⚠️ Не удалось конвертировать \(amount) \(currency) в \(targetAccount.currency) для депозита-получателя")
            targetAmount = amount
        }
        
        if var targetDepositInfo = targetAccount.depositInfo {
            let amountDecimal = Decimal(targetAmount)
            targetDepositInfo.principalBalance += amountDecimal
            accounts[targetIndex].depositInfo = targetDepositInfo
            // Обновляем баланс счета на основе depositInfo
            var totalBalance: Decimal = targetDepositInfo.principalBalance
            if !targetDepositInfo.capitalizationEnabled {
                totalBalance += targetDepositInfo.interestAccruedNotCapitalized
            }
            accounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
        } else {
            // Для обычных счетов просто увеличиваем баланс
            accounts[targetIndex].balance += targetAmount
        }

        // Сохраняем как internalTransfer-транзакцию
        let createdAt = Date().timeIntervalSince1970
        let id = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .internalTransfer,
            currency: currency,
            createdAt: createdAt
        )

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Перевод",
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970 // Новая транзакция - текущее время
        )

        // Оптимизированная вставка вместо полной сортировки
        insertTransactionsSorted([transferTx])
        saveToStorage()
    }
    
    // MARK: - Deposits
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.addDeposit instead
    @available(*, deprecated, message: "Use DepositsViewModel.addDeposit instead")
    func addDeposit(
        name: String,
        currency: String,
        bankName: String,
        bankLogo: BankLogo,
        principalBalance: Decimal,
        interestRateAnnual: Decimal,
        interestPostingDay: Int,
        capitalizationEnabled: Bool = true
    ) {
        let depositInfo = DepositInfo(
            bankName: bankName,
            principalBalance: principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRateAnnual,
            interestPostingDay: interestPostingDay
        )
        
        let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
        let account = Account(
            name: name,
            balance: balance,
            currency: currency,
            bankLogo: bankLogo,
            depositInfo: depositInfo
        )
        
        accounts.append(account)
        initialAccountBalances[account.id] = balance
        recalculateAccountBalances()
        saveToStorage()
        
        // Сразу делаем reconcile для расчета процентов до сегодня
        // Note: Deposit reconciliation should be handled by DepositsViewModel
        // This deprecated method call has been removed
    }
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.updateDeposit instead
    @available(*, deprecated, message: "Use DepositsViewModel.updateDeposit instead")
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            if let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                initialAccountBalances[account.id] = balance
            }
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.deleteDeposit instead
    @available(*, deprecated, message: "Use DepositsViewModel.deleteDeposit instead")
    func deleteDeposit(_ account: Account) {
        deleteAccount(account) // Используем существующий метод deleteAccount
    }
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.addDepositRateChange instead
    @available(*, deprecated, message: "Use DepositsViewModel.addDepositRateChange instead")
    func addDepositRateChange(accountId: String, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }),
              var depositInfo = accounts[index].depositInfo else {
            return
        }
        
        DepositInterestService.addRateChange(
            depositInfo: &depositInfo,
            effectiveFrom: effectiveFrom,
            annualRate: annualRate,
            note: note
        )
        
        accounts[index].depositInfo = depositInfo
        recalculateAccountBalances()
        saveToStorage()
        
        // Пересчитываем проценты после изменения ставки
        // Note: Deposit reconciliation should be handled by DepositsViewModel
        // This deprecated method call has been removed
    }
    
    /// ⚠️ DEPRECATED: Use DepositsViewModel.reconcileAllDeposits instead
    @available(*, deprecated, message: "Use DepositsViewModel.reconcileAllDeposits instead")
    func reconcileAllDeposits() {
        for index in accounts.indices where accounts[index].isDeposit {
            DepositInterestService.reconcileDepositInterest(
                account: &accounts[index],
                allTransactions: allTransactions,
                onTransactionCreated: { [weak self] transaction in
                    self?.insertTransactionsSorted([transaction])
                }
            )
        }
        
        if accounts.contains(where: { $0.isDeposit }) {
            saveToStorage()
        }
    }
    
    // MARK: - Helper Methods

    /// Оптимизированная вставка новых транзакций в отсортированный массив
    /// Вместо полной сортировки O(n log n), делаем incremental insert O(n×m) где m << n
    private func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        guard !newTransactions.isEmpty else { return }

        // Сортируем только новые транзакции
        let sortedNew = newTransactions.sorted { $0.date > $1.date }

        // Если массив пуст, просто присваиваем
        if allTransactions.isEmpty {
            allTransactions = sortedNew
            return
        }

        // Incremental insert: вставляем каждую транзакцию в правильную позицию
        for newTransaction in sortedNew {
            // Находим позицию для вставки (первый элемент меньше или равный новому)
            if let insertIndex = allTransactions.firstIndex(where: { $0.date <= newTransaction.date }) {
                allTransactions.insert(newTransaction, at: insertIndex)
            } else {
                // Если не нашли такой элемент, добавляем в конец
                allTransactions.append(newTransaction)
            }
        }
    }

    private func applyRules(to transactions: [Transaction]) -> [Transaction] {
        guard !categoryRules.isEmpty else { return transactions }
        
        let rulesMap = Dictionary(
            uniqueKeysWithValues: categoryRules.map { ($0.description.lowercased(), $0) }
        )
        
        return transactions.map { transaction in
            if let rule = rulesMap[transaction.description.lowercased()] {
                return Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: rule.category,
                    subcategory: rule.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: transaction.recurringSeriesId,
                    recurringOccurrenceId: transaction.recurringOccurrenceId,
                    createdAt: transaction.createdAt // Сохраняем оригинальный createdAt
                )
            }
            return transaction
        }
    }
    
    func saveToStorage() {
        // Используем repository для сохранения всех данных
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveToStorage")

            // Создаём копии данных на main thread
            let transactions = await MainActor.run { self.allTransactions }
            let rules = await MainActor.run { self.categoryRules }
            let accs = await MainActor.run { self.accounts }
            let categories = await MainActor.run { self.customCategories }
            let series = await MainActor.run { self.recurringSeries }
            let occurrences = await MainActor.run { self.recurringOccurrences }
            let subcats = await MainActor.run { self.subcategories }
            let catLinks = await MainActor.run { self.categorySubcategoryLinks }
            let txLinks = await MainActor.run { self.transactionSubcategoryLinks }

            // Сохраняем через repository
            await MainActor.run {
                self.repository.saveTransactions(transactions)
                self.repository.saveCategoryRules(rules)
                self.repository.saveAccounts(accs)
                self.repository.saveCategories(categories)
                self.repository.saveRecurringSeries(series)
                self.repository.saveRecurringOccurrences(occurrences)
                self.repository.saveSubcategories(subcats)
                self.repository.saveCategorySubcategoryLinks(catLinks)
                self.repository.saveTransactionSubcategoryLinks(txLinks)
            }

            PerformanceProfiler.end("saveToStorage")
        }
    }
    
    private func loadFromStorage() {
        // Загружаем данные через repository
        allTransactions = repository.loadTransactions()
        categoryRules = repository.loadCategoryRules()
        accounts = repository.loadAccounts()
        
        // Инициализируем начальные балансы из загруженных счетов
        for account in accounts {
            if initialAccountBalances[account.id] == nil {
                initialAccountBalances[account.id] = account.balance
            }
        }
        
        customCategories = repository.loadCategories()
        recurringSeries = repository.loadRecurringSeries()
        recurringOccurrences = repository.loadRecurringOccurrences()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
        
        recalculateAccountBalances()
        // reconcileAllDeposits вызывается асинхронно в init() после generateRecurringTransactions
    }
    
    func recalculateAccountBalances() {
        guard !accounts.isEmpty else { return }

        // Сбрасываем предупреждение о конвертации валют
        currencyConversionWarning = nil

        // Создаем словарь для расчета изменений балансов от транзакций
        var balanceChanges: [String: Double] = [:]
        for account in accounts {
            balanceChanges[account.id] = 0
            // Если начальный баланс еще не сохранен, сохраняем текущий
            if initialAccountBalances[account.id] == nil {
                initialAccountBalances[account.id] = account.balance
            }
        }

        // Рассчитываем изменения балансов от всех транзакций
        // Исключаем транзакции с будущей датой (они еще не выполнены)
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter

        // Флаг для отслеживания проблем с конвертацией
        var hasConversionIssues = false
        
        for tx in allTransactions {
            // Исключаем транзакции с будущей датой из расчета балансов
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }
            
            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    // Для дохода: используем convertedAmount (если есть) в валюте счета
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] += amountToUse
                }
            case .expense:
                if let accountId = tx.accountId {
                    // Для расхода: используем convertedAmount (если есть) в валюте счета
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] -= amountToUse
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Транзакции депозита не учитываются в балансе через этот механизм
                // Баланс депозита управляется через depositInfo
                break
            case .internalTransfer:
                // Для перевода: используем разные суммы для source и target счетов
                if let sourceId = tx.accountId,
                   let sourceAccount = accounts.first(where: { $0.id == sourceId }) {
                    // Источник: используем convertedAmount (если есть) или amount, но в валюте источника
                    let sourceAmount: Double
                    if tx.currency == sourceAccount.currency {
                        // Валюты совпадают - используем amount
                        sourceAmount = tx.amount
                    } else if let converted = tx.convertedAmount {
                        // Если есть convertedAmount, значит конвертация уже была в валюту источника
                        sourceAmount = converted
                    } else {
                        // Если нет convertedAmount и валюты разные, пытаемся конвертировать через кэш
                        if let converted = CurrencyConverter.convertSync(
                            amount: tx.amount,
                            from: tx.currency,
                            to: sourceAccount.currency
                        ) {
                            sourceAmount = converted
                        } else {
                            // Если конвертация невозможна, используем amount и выводим предупреждение
                            print("⚠️ Не удалось конвертировать \(tx.amount) \(tx.currency) в \(sourceAccount.currency) для счета-источника. Баланс может быть неточным.")
                            hasConversionIssues = true
                            sourceAmount = tx.amount
                        }
                    }
                    balanceChanges[sourceId, default: 0] -= sourceAmount
                }

                if let targetId = tx.targetAccountId,
                   let targetAccount = accounts.first(where: { $0.id == targetId }) {
                    // Получатель: нужно конвертировать в валюту получателя
                    let targetAmount: Double
                    if tx.currency == targetAccount.currency {
                        // Валюты совпадают - используем amount
                        targetAmount = tx.amount
                    } else if let converted = CurrencyConverter.convertSync(
                        amount: tx.amount,
                        from: tx.currency,
                        to: targetAccount.currency
                    ) {
                        // Валюты разные - конвертируем через кэш синхронно
                        targetAmount = converted
                    } else {
                        // Если конвертация невозможна (нет курсов в кэше), выводим предупреждение
                        // и используем amount без конвертации (будет неточный баланс)
                        print("⚠️ Не удалось конвертировать \(tx.amount) \(tx.currency) в \(targetAccount.currency) для счета-получателя. Баланс может быть неточным.")
                        print("⚠️ Перевод ID: \(tx.id), Описание: \(tx.description)")
                        print("⚠️ Курсы валют не загружены в кэш. Проверьте подключение к интернету и перезапустите приложение.")
                        hasConversionIssues = true
                        targetAmount = tx.amount
                    }
                    balanceChanges[targetId, default: 0] += targetAmount
                }
            }
        }

        // Обновляем балансы: начальный баланс + изменения от транзакций
        // Для депозитов баланс управляется через depositInfo, не через транзакции
        for index in accounts.indices {
            let accountId = accounts[index].id
            
            if accounts[index].isDeposit {
                // Для депозитов баланс уже установлен через depositInfo
                // Просто убеждаемся, что баланс синхронизирован с depositInfo
                if let depositInfo = accounts[index].depositInfo {
                    var totalBalance: Decimal = depositInfo.principalBalance
                    if !depositInfo.capitalizationEnabled {
                        totalBalance += depositInfo.interestAccruedNotCapitalized
                    }
                    accounts[index].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                }
            } else {
                // Для обычных счетов: начальный баланс + изменения от транзакций
                let initialBalance = initialAccountBalances[accountId] ?? accounts[index].balance
                let changes = balanceChanges[accountId] ?? 0
                accounts[index].balance = initialBalance + changes
            }
        }

        // Если были проблемы с конвертацией, устанавливаем предупреждение
        if hasConversionIssues {
            currencyConversionWarning = "Не удалось конвертировать валюты для некоторых переводов. Балансы могут быть неточными. Проверьте подключение к интернету."
        }
    }
    
    // MARK: - Recurring Transactions
    
    func createRecurringSeries(
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String?,
        description: String,
        accountId: String?,
        targetAccountId: String?,
        frequency: RecurringFrequency,
        startDate: String
    ) -> RecurringSeries {
        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category,
            subcategory: subcategory,
            description: description,
            accountId: accountId,
            targetAccountId: targetAccountId,
            frequency: frequency,
            startDate: startDate
        )
        recurringSeries.append(series)
        saveToStorage()
        generateRecurringTransactions()
        return series
    }
    
    func updateRecurringSeries(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]
            
            // Если изменилась частота, нужно удалить все будущие транзакции и перегенерировать
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate
            
            // Обновляем серию
            recurringSeries[index] = series
            
            if frequencyChanged || startDateChanged {
                // Удаляем все будущие транзакции этой серии
                let today = Calendar.current.startOfDay(for: Date())
                let dateFormatter = Self.dateFormatter
                
                // Удаляем все будущие транзакции (дата > today) этой серии
                let futureOccurrences = recurringOccurrences.filter { occurrence in
                    guard occurrence.seriesId == series.id,
                          let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                        return false
                    }
                    return occurrenceDate > today
                }
                
                // Удаляем транзакции и occurrences
                for occurrence in futureOccurrences {
                    allTransactions.removeAll { $0.id == occurrence.transactionId }
                    recurringOccurrences.removeAll { $0.id == occurrence.id }
                }
            }
            
            saveToStorage()
            generateRecurringTransactions()
        }
    }
    
    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            recurringSeries[index].isActive = false
            saveToStorage()
            // Не вызываем generateRecurringTransactions() здесь, так как удаление будущих транзакций 
            // должно происходить в UI после остановки серии
        }
    }
    
    func deleteRecurringSeries(_ seriesId: String) {
        // Удаляем все occurrences
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        // Удаляем серию
        recurringSeries.removeAll { $0.id == seriesId }
        saveToStorage()
        
        // Cancel notifications for subscriptions
        Task {
            await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
        }
    }
    
    // MARK: - Subscriptions
    
    /// Get all subscriptions
    var subscriptions: [RecurringSeries] {
        recurringSeries.filter { $0.isSubscription }
    }
    
    /// Get active subscriptions
    var activeSubscriptions: [RecurringSeries] {
        subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
    }
    
    /// Create a new subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.createSubscription instead
    @available(*, deprecated, message: "Use SubscriptionsViewModel.createSubscription instead")
    func createSubscription(
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String?,
        description: String,
        accountId: String?,
        frequency: RecurringFrequency,
        startDate: String,
        brandLogo: BankLogo?,
        brandId: String?,
        reminderOffsets: [Int]?
    ) -> RecurringSeries {
        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category,
            subcategory: subcategory,
            description: description,
            accountId: accountId,
            targetAccountId: nil,
            frequency: frequency,
            startDate: startDate,
            kind: .subscription,
            brandLogo: brandLogo,
            brandId: brandId,
            reminderOffsets: reminderOffsets,
            status: .active
        )
        recurringSeries.append(series)
        saveToStorage()
        generateRecurringTransactions()
        
        // Schedule notifications
        Task {
            if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
            }
        }
        
        return series
    }
    
    /// Update a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.updateSubscription instead
    @available(*, deprecated, message: "Use SubscriptionsViewModel.updateSubscription instead")
    func updateSubscription(_ series: RecurringSeries) {
        if let index = recurringSeries.firstIndex(where: { $0.id == series.id }) {
            let oldSeries = recurringSeries[index]
            
            // If frequency or start date changed, remove future transactions
            let frequencyChanged = oldSeries.frequency != series.frequency
            let startDateChanged = oldSeries.startDate != series.startDate
            
            recurringSeries[index] = series
            
            if frequencyChanged || startDateChanged {
                // Remove all future transactions for this series
                let today = Calendar.current.startOfDay(for: Date())
                let dateFormatter = Self.dateFormatter
                
                let futureOccurrences = recurringOccurrences.filter { occurrence in
                    guard occurrence.seriesId == series.id,
                          let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                        return false
                    }
                    return occurrenceDate > today
                }
                
                for occurrence in futureOccurrences {
                    allTransactions.removeAll { $0.id == occurrence.transactionId }
                    recurringOccurrences.removeAll { $0.id == occurrence.id }
                }
            }
            
            saveToStorage()
            generateRecurringTransactions()
            
            // Update notifications
            Task {
                if series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                } else {
                    await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
                }
            }
        }
    }
    
    /// Pause a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.pauseSubscription instead
    @available(*, deprecated, message: "Use SubscriptionsViewModel.pauseSubscription instead")
    func pauseSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            recurringSeries[index].status = .paused
            recurringSeries[index].isActive = false
            saveToStorage()
            
            // Cancel notifications
            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }
    
    /// Resume a subscription
    /// ⚠️ DEPRECATED: Use SubscriptionsViewModel.resumeSubscription instead
    @available(*, deprecated, message: "Use SubscriptionsViewModel.resumeSubscription instead")
    func resumeSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            recurringSeries[index].status = .active
            recurringSeries[index].isActive = true
            saveToStorage()
            generateRecurringTransactions()
            
            // Schedule notifications
            Task {
                if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: recurringSeries[index]) {
                    await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: recurringSeries[index], nextChargeDate: nextChargeDate)
                }
            }
        }
    }
    
    /// Archive a subscription
    func archiveSubscription(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId && $0.isSubscription }) {
            recurringSeries[index].status = .archived
            recurringSeries[index].isActive = false
            saveToStorage()
            
            // Cancel notifications
            Task {
                await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)
            }
        }
    }
    
    /// Get transactions for a subscription
    func transactions(for subscriptionId: String) -> [Transaction] {
        allTransactions.filter { $0.recurringSeriesId == subscriptionId }
            .sorted { $0.date > $1.date }
    }
    
    /// Get next charge date for a subscription
    func nextChargeDate(for subscriptionId: String) -> Date? {
        guard let series = recurringSeries.first(where: { $0.id == subscriptionId && $0.isSubscription }) else {
            return nil
        }
        return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
    }
    
    // Используем кешированный TimeFormatter из утилит
    private static var timeFormatter: DateFormatter {
        DateFormatters.timeFormatter
    }
    
    // Основная версия для вызова из других мест (синхронная, но оптимизированная)
    func generateRecurringTransactions() {
        // Используем кэшированные форматтеры
        let dateFormatter = Self.dateFormatter

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Уменьшаем горизонт генерации с 12 до 3 месяцев для производительности
        guard let horizonDate = calendar.date(byAdding: .month, value: 3, to: today) else {
            return
        }
        
        // Оптимизация: создаем Set существующих transaction IDs для быстрой проверки
        let existingTransactionIds = Set(allTransactions.map { $0.id })
        
        // Оптимизация: создаем Set существующих occurrences для быстрой проверки
        var existingOccurrenceKeys: Set<String> = []
        for occurrence in recurringOccurrences {
            existingOccurrenceKeys.insert("\(occurrence.seriesId):\(occurrence.occurrenceDate)")
        }
        
        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []
        
        // Автоматически выполняем recurring операции, срок которых наступил (включая сегодня)
        // Recurring операции с датой сегодня сразу становятся выполненными (обычными транзакциями)
        var hasChanges = false
        for i in allTransactions.indices {
            let transaction = allTransactions[i]
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate <= today {
                // Срок наступил (включая сегодня) - помечаем как выполненную (убираем recurringSeriesId)
                // Recurring операции с датой сегодня сразу становятся обычными транзакциями
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: transaction.category,
                    subcategory: transaction.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: nil, // Убираем связь с recurring - становимся обычной транзакцией
                    recurringOccurrenceId: nil,
                    createdAt: transaction.createdAt // Сохраняем оригинальный createdAt
                )
                allTransactions[i] = updatedTransaction
                hasChanges = true
            }
        }
        
        for series in recurringSeries where series.isActive {
            guard let startDate = dateFormatter.date(from: series.startDate) else { continue }
            
            // Если серия начинается сегодня или раньше, первая транзакция должна быть на завтра (или следующую дату)
            // Recurring операции с датой сегодня автоматически выполняются и становятся обычными транзакциями
            var currentDate: Date
            if startDate <= today {
                // Серия уже началась или начинается сегодня - начинаем генерацию со следующей даты по частоте
                guard let nextDate = {
                    switch series.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: today)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: today)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: today)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: today)
                    }
                }() else {
                    continue // Если не удалось вычислить следующую дату, пропускаем серию
                }
                currentDate = nextDate
            } else {
                // Серия начинается в будущем - начинаем с startDate
                currentDate = startDate
            }
            
            // Генерируем транзакции на горизонт 3 месяцев (начиная с первой будущей даты)
            while currentDate <= horizonDate {
                let dateString = dateFormatter.string(from: currentDate)
                let occurrenceKey = "\(series.id):\(dateString)"
                
                // Быстрая проверка через Set
                if !existingOccurrenceKeys.contains(occurrenceKey) {
                    let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
                    
                    // Для recurring транзакций используем дату транзакции как createdAt (чтобы они сортировались по дате выполнения)
                    let transactionDate = dateFormatter.date(from: dateString) ?? Date()
                    let createdAt = transactionDate.timeIntervalSince1970
                    
                    let transactionId = TransactionIDGenerator.generateID(
                        date: dateString,
                        description: series.description,
                        amount: amountDouble,
                        type: .expense,
                        currency: series.currency,
                        createdAt: createdAt
                    )
                    
                    // Проверяем, нет ли уже такой транзакции
                    if !existingTransactionIds.contains(transactionId) {
                        let occurrenceId = UUID().uuidString
                        let transaction = Transaction(
                            id: transactionId,
                            date: dateString,
                            description: series.description,
                            amount: amountDouble,
                            currency: series.currency,
                            convertedAmount: nil,
                            type: .expense,
                            category: series.category,
                            subcategory: series.subcategory,
                            accountId: series.accountId,
                            targetAccountId: series.targetAccountId,
                            recurringSeriesId: series.id,
                            recurringOccurrenceId: occurrenceId,
                            createdAt: createdAt // Используем дату транзакции для сортировки
                        )
                        
                        let occurrence = RecurringOccurrence(
                            id: occurrenceId,
                            seriesId: series.id,
                            occurrenceDate: dateString,
                            transactionId: transactionId
                        )
                        
                        newTransactions.append(transaction)
                        newOccurrences.append(occurrence)
                        existingOccurrenceKeys.insert(occurrenceKey)
                    }
                }
                
                // Переходим к следующей дате
                guard let nextDate = {
                    switch series.frequency {
                    case .daily:
                        return calendar.date(byAdding: .day, value: 1, to: currentDate)
                    case .weekly:
                        return calendar.date(byAdding: .day, value: 7, to: currentDate)
                    case .monthly:
                        return calendar.date(byAdding: .month, value: 1, to: currentDate)
                    case .yearly:
                        return calendar.date(byAdding: .year, value: 1, to: currentDate)
                    }
                }() else {
                    break // Если не удалось вычислить следующую дату, прерываем цикл
                }
                currentDate = nextDate
            }
        }
        
        // Добавляем новые транзакции и occurrences только если они есть
        if !newTransactions.isEmpty {
            // Используем оптимизированную вставку
            insertTransactionsSorted(newTransactions)
            recurringOccurrences.append(contentsOf: newOccurrences)
            recalculateAccountBalances()
            saveToStorage()
            
            // Update notifications for subscriptions after generating transactions
            Task {
                for series in recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        } else if hasChanges {
            // Если были изменения в recurring (автоматическое выполнение), пересчитываем балансы и сохраняем
            recalculateAccountBalances()
            saveToStorage()
            
            // Update notifications for subscriptions after changes
            Task {
                for series in recurringSeries where series.isSubscription && series.subscriptionStatus == .active {
                    if let nextChargeDate = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series) {
                        await SubscriptionNotificationScheduler.shared.scheduleNotifications(for: series, nextChargeDate: nextChargeDate)
                    }
                }
            }
        }
    }
    
    func updateRecurringTransaction(_ transactionId: String, updateAllFuture: Bool, newAmount: Decimal? = nil, newCategory: String? = nil, newSubcategory: String? = nil) {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }),
              let seriesId = transaction.recurringSeriesId,
              let seriesIndex = recurringSeries.firstIndex(where: { $0.id == seriesId }) else {
            return
        }
        
        if updateAllFuture {
            // Обновляем серию
            if let newAmount = newAmount {
                recurringSeries[seriesIndex].amount = newAmount
            }
            if let newCategory = newCategory {
                recurringSeries[seriesIndex].category = newCategory
            }
            if let newSubcategory = newSubcategory {
                recurringSeries[seriesIndex].subcategory = newSubcategory
            }
            
            // Удаляем все будущие транзакции этой серии
            let dateFormatter = Self.dateFormatter // Используем кешированный форматтер
            guard let transactionDate = dateFormatter.date(from: transaction.date) else { return }

            let futureOccurrences = recurringOccurrences.filter { occurrence in
                guard occurrence.seriesId == seriesId,
                      let occurrenceDate = dateFormatter.date(from: occurrence.occurrenceDate) else {
                    return false
                }
                return occurrenceDate >= transactionDate
            }
            
            for occurrence in futureOccurrences {
                allTransactions.removeAll { $0.id == occurrence.transactionId }
                recurringOccurrences.removeAll { $0.id == occurrence.id }
            }
            
            // Перегенерируем будущие транзакции
            generateRecurringTransactions()
        } else {
            // Обновляем только эту транзакцию
            if let index = allTransactions.firstIndex(where: { $0.id == transactionId }) {
                var updatedTransaction = allTransactions[index]
                if let newAmount = newAmount {
                    let amountDouble = NSDecimalNumber(decimal: newAmount).doubleValue
                    updatedTransaction = Transaction(
                        id: updatedTransaction.id,
                        date: updatedTransaction.date,
                        description: updatedTransaction.description,
                        amount: amountDouble,
                        currency: updatedTransaction.currency,
                        convertedAmount: updatedTransaction.convertedAmount,
                        type: updatedTransaction.type,
                        category: newCategory ?? updatedTransaction.category,
                        subcategory: newSubcategory ?? updatedTransaction.subcategory,
                        accountId: updatedTransaction.accountId,
                        targetAccountId: updatedTransaction.targetAccountId,
                        recurringSeriesId: updatedTransaction.recurringSeriesId,
                        recurringOccurrenceId: updatedTransaction.recurringOccurrenceId,
                        createdAt: updatedTransaction.createdAt // Сохраняем оригинальный createdAt
                    )
                    allTransactions[index] = updatedTransaction
                }
            }
        }
        
        saveToStorage()
    }
    
    // MARK: - Subcategories
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.addSubcategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.addSubcategory instead")
    func addSubcategory(name: String) -> Subcategory {
        let subcategory = Subcategory(name: name)
        subcategories.append(subcategory)
        saveToStorage()
        return subcategory
    }
    
    func updateSubcategory(_ subcategory: Subcategory) {
        if let index = subcategories.firstIndex(where: { $0.id == subcategory.id }) {
            subcategories[index] = subcategory
            saveToStorage()
        }
    }
    
    func deleteSubcategory(_ subcategoryId: String) {
        // Удаляем связи с категориями
        categorySubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        // Удаляем связи с транзакциями (оставляем транзакции, но убираем линк)
        transactionSubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        // Удаляем подкатегорию
        subcategories.removeAll { $0.id == subcategoryId }
        saveToStorage()
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.linkSubcategoryToCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.linkSubcategoryToCategory instead")
    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        // Проверяем, нет ли уже такой связи
        let existingLink = categorySubcategoryLinks.first { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        
        if existingLink == nil {
            let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
            categorySubcategoryLinks.append(link)
            saveToStorage()
        }
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.unlinkSubcategoryFromCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.unlinkSubcategoryFromCategory instead")
    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        categorySubcategoryLinks.removeAll { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        saveToStorage()
    }
    
    /// ⚠️ DEPRECATED: Use CategoriesViewModel.getSubcategoriesForCategory instead
    @available(*, deprecated, message: "Use CategoriesViewModel.getSubcategoriesForCategory instead")
    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        let linkedSubcategoryIds = categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }
        
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }
    
    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = transactionSubcategoryLinks
            .filter { $0.transactionId == transactionId }
            .map { $0.subcategoryId }
        
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }
    
    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        // Удаляем старые связи
        transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }
        
        // Добавляем новые связи
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            transactionSubcategoryLinks.append(link)
        }
        
        saveToStorage()
    }
    
    func searchSubcategories(query: String) -> [Subcategory] {
        let queryLower = query.lowercased()
        return subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }
}

// DateFilter удален - теперь используется TimeFilterManager

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
