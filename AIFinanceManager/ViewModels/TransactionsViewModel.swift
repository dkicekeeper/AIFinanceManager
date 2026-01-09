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
    
    // Храним начальные балансы счетов (баланс при создании/редактировании)
    private var initialAccountBalances: [String: Double] = [:]
    
    // Кеш для summary
    private var cachedSummary: Summary?
    private var summaryCacheInvalidated = true
    
    // Кеш для categoryExpenses
    private var cachedCategoryExpenses: [String: CategoryExpense]?
    private var categoryExpensesCacheInvalidated = true
    
    private let storageKeyTransactions = "allTransactions"
    private let storageKeyRules = "categoryRules"
    private let storageKeyAccounts = "accounts"
    private let storageKeyCustomCategories = "customCategories"
    private let storageKeyRecurringSeries = "recurringSeries"
    private let storageKeyRecurringOccurrences = "recurringOccurrences"
    private let storageKeySubcategories = "subcategories"
    private let storageKeyCategorySubcategoryLinks = "categorySubcategoryLinks"
    private let storageKeyTransactionSubcategoryLinks = "transactionSubcategoryLinks"
    
    init() {
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
        // Используем filteredTransactions, который учитывает selectedCategories
        return filteredTransactions.filter { transaction in
            guard let transactionDate = Self.dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= range.start && transactionDate < range.end
        }
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
            if date1 != date2 {
                return date1 > date2
            }
            // Если даты равны, сортируем по времени
            if let time1 = tx1.time, let time2 = tx2.time {
                return time1 > time2
            }
            return false
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
        
        // Оптимизация: один проход вместо множественных фильтров
        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        var plannedAmount: Double = 0
        
        for transaction in filtered {
            // Используем convertedAmount, если он есть (сумма в валюте счета)
            let amountToUse = transaction.convertedAmount ?? transaction.amount
            
            let isFutureRecurring: Bool
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate >= today {
                isFutureRecurring = true
                plannedAmount += amountToUse
            } else {
                isFutureRecurring = false
            }
            
            // Учитываем только выполненные транзакции
            if !isFutureRecurring {
                switch transaction.type {
                case .income:
                    totalIncome += amountToUse
                case .expense:
                    totalExpenses += amountToUse
                case .internalTransfer:
                    totalInternal += amountToUse
                }
            }
        }
        
        let currency = allTransactions.first?.currency ?? "USD"
        let dates = allTransactions.map { $0.date }.sorted()
        
        let result = Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: currency,
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
        
        for transaction in filtered {
            let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category
            // Используем convertedAmount, если он есть (сумма в валюте счета)
            let amountToUse = transaction.convertedAmount ?? transaction.amount

            // Безопасное обновление без force unwrap
            var expense = result[category] ?? CategoryExpense(total: 0, subcategories: [:])
            expense.total += amountToUse

            if let subcategory = transaction.subcategory {
                expense.subcategories[subcategory, default: 0] += amountToUse
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
                time: transaction.time,
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
                recurringOccurrenceId: transaction.recurringOccurrenceId
            )
        }
        
        let transactionsWithRules = applyRules(to: processedTransactions)
        
        // Remove duplicates
        let existingIDs = Set(allTransactions.map { $0.id })
        let uniqueNew = transactionsWithRules.filter { !existingIDs.contains($0.id) }
        
        if !uniqueNew.isEmpty {
            // Автоматически создаем категории для новых транзакций
            createCategoriesForTransactions(uniqueNew)
            
            allTransactions.append(contentsOf: uniqueNew)
            allTransactions.sort { $0.date > $1.date }
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
                let iconName = CategoryEmoji.iconName(for: categoryName, type: transaction.type, customCategories: customCategories)
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
            let id = TransactionIDGenerator.generateID(
                date: transaction.date,
                description: formattedDescription,
                amount: transaction.amount,
                type: transaction.type,
                currency: transaction.currency
            )
            transactionWithID = Transaction(
                id: id,
                date: transaction.date,
                time: transaction.time,
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
                recurringOccurrenceId: transaction.recurringOccurrenceId
            )
        } else {
            transactionWithID = Transaction(
                id: transaction.id,
                date: transaction.date,
                time: transaction.time,
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
                recurringOccurrenceId: transaction.recurringOccurrenceId
            )
        }
        
        let transactionsWithRules = applyRules(to: [transactionWithID])
        let existingIDs = Set(allTransactions.map { $0.id })
        
        if !existingIDs.contains(transactionWithID.id) {
            // Создаем категорию, если нужно
            createCategoriesForTransactions(transactionsWithRules)
            
            allTransactions.append(contentsOf: transactionsWithRules)
            allTransactions.sort { $0.date > $1.date }
            invalidateCaches()
            recalculateAccountBalances()
            saveToStorage()
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
                    time: allTransactions[i].time,
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
                    recurringOccurrenceId: allTransactions[i].recurringOccurrenceId
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
        
        // Удаляем все данные из UserDefaults
        UserDefaults.standard.removeObject(forKey: storageKeyTransactions)
        UserDefaults.standard.removeObject(forKey: storageKeyRules)
        UserDefaults.standard.removeObject(forKey: storageKeyAccounts)
        UserDefaults.standard.removeObject(forKey: storageKeyCustomCategories)
        UserDefaults.standard.removeObject(forKey: storageKeyRecurringSeries)
        UserDefaults.standard.removeObject(forKey: storageKeyRecurringOccurrences)
        UserDefaults.standard.removeObject(forKey: storageKeySubcategories)
        UserDefaults.standard.removeObject(forKey: storageKeyCategorySubcategoryLinks)
        UserDefaults.standard.removeObject(forKey: storageKeyTransactionSubcategoryLinks)
        
        // Синхронизируем изменения
        UserDefaults.standard.synchronize()
        
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
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        invalidateCaches()
        saveToStorage()
    }
    
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
                        time: allTransactions[i].time,
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
                        recurringOccurrenceId: allTransactions[i].recurringOccurrenceId
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
    
    func deleteCategory(_ category: CustomCategory) {
        customCategories.removeAll { $0.id == category.id }
        invalidateCaches()
        saveToStorage()
    }
    
    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    // MARK: - Accounts

    func addAccount(name: String, balance: Double, currency: String, bankLogo: BankLogo = .none) {
        let account = Account(name: name, balance: balance, currency: currency, bankLogo: bankLogo)
        accounts.append(account)
        // Сохраняем начальный баланс
        initialAccountBalances[account.id] = balance
        recalculateAccountBalances()
        saveToStorage()
    }

    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            // Обновляем начальный баланс при редактировании
            initialAccountBalances[account.id] = account.balance
            recalculateAccountBalances()
            saveToStorage()
        }
    }
    
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

        // Обновляем балансы
        accounts[sourceIndex].balance -= amount
        accounts[targetIndex].balance += amount

        // Сохраняем как internalTransfer-транзакцию
        let id = TransactionIDGenerator.generateID(
            date: date,
            description: description,
            amount: amount,
            type: .internalTransfer,
            currency: currency
        )

        let transferTx = Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Transfer",
            subcategory: nil,
            accountId: sourceId,
            targetAccountId: targetId
        )

        allTransactions.append(transferTx)
        allTransactions.sort { $0.date > $1.date }
        saveToStorage()
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
                    subcategory: rule.subcategory
                )
            }
            return transaction
        }
    }
    
    func saveToStorage() {
        // Выполняем сохранение асинхронно на background queue
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveToStorage")

            let encoder = JSONEncoder()

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

            // Кодируем на background thread
            if let encoded = try? encoder.encode(transactions) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyTransactions)
            }
            if let encoded = try? encoder.encode(rules) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRules)
            }
            if let encoded = try? encoder.encode(accs) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyAccounts)
            }
            if let encoded = try? encoder.encode(categories) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyCustomCategories)
            }
            if let encoded = try? encoder.encode(series) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRecurringSeries)
            }
            if let encoded = try? encoder.encode(occurrences) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRecurringOccurrences)
            }
            if let encoded = try? encoder.encode(subcats) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeySubcategories)
            }
            if let encoded = try? encoder.encode(catLinks) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyCategorySubcategoryLinks)
            }
            if let encoded = try? encoder.encode(txLinks) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyTransactionSubcategoryLinks)
            }

            PerformanceProfiler.end("saveToStorage")
        }
    }
    
    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKeyTransactions),
           let decoded = try? JSONDecoder().decode([Transaction].self, from: data) {
            allTransactions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyRules),
           let decoded = try? JSONDecoder().decode([CategoryRule].self, from: data) {
            categoryRules = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyAccounts),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
            // Инициализируем начальные балансы из загруженных счетов
            for account in accounts {
                if initialAccountBalances[account.id] == nil {
                    initialAccountBalances[account.id] = account.balance
                }
            }
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyCustomCategories),
           let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) {
            customCategories = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyRecurringSeries),
           let decoded = try? JSONDecoder().decode([RecurringSeries].self, from: data) {
            recurringSeries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyRecurringOccurrences),
           let decoded = try? JSONDecoder().decode([RecurringOccurrence].self, from: data) {
            recurringOccurrences = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeySubcategories),
           let decoded = try? JSONDecoder().decode([Subcategory].self, from: data) {
            subcategories = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyCategorySubcategoryLinks),
           let decoded = try? JSONDecoder().decode([CategorySubcategoryLink].self, from: data) {
            categorySubcategoryLinks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: storageKeyTransactionSubcategoryLinks),
           let decoded = try? JSONDecoder().decode([TransactionSubcategoryLink].self, from: data) {
            transactionSubcategoryLinks = decoded
        }
        recalculateAccountBalances()
    }

    func recalculateAccountBalances() {
        guard !accounts.isEmpty else { return }

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
        for tx in allTransactions {
            // Используем convertedAmount, если он есть (сумма в валюте счета)
            let amountToUse = tx.convertedAmount ?? tx.amount
            
            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    balanceChanges[accountId, default: 0] += amountToUse
                }
            case .expense:
                if let accountId = tx.accountId {
                    balanceChanges[accountId, default: 0] -= amountToUse
                }
            case .internalTransfer:
                if let sourceId = tx.accountId {
                    balanceChanges[sourceId, default: 0] -= amountToUse
                }
                if let targetId = tx.targetAccountId {
                    balanceChanges[targetId, default: 0] += amountToUse
                }
            }
        }

        // Обновляем балансы: начальный баланс + изменения от транзакций
        for index in accounts.indices {
            let accountId = accounts[index].id
            let initialBalance = initialAccountBalances[accountId] ?? accounts[index].balance
            let changes = balanceChanges[accountId] ?? 0
            accounts[index].balance = initialBalance + changes
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
            recurringSeries[index] = series
            saveToStorage()
            generateRecurringTransactions()
        }
    }
    
    func stopRecurringSeries(_ seriesId: String) {
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            recurringSeries[index].isActive = false
            saveToStorage()
        }
    }
    
    func deleteRecurringSeries(_ seriesId: String) {
        // Удаляем все occurrences
        recurringOccurrences.removeAll { $0.seriesId == seriesId }
        // Удаляем серию
        recurringSeries.removeAll { $0.id == seriesId }
        saveToStorage()
    }
    
    // Используем кешированный TimeFormatter из утилит
    private static var timeFormatter: DateFormatter {
        DateFormatters.timeFormatter
    }
    
    // Основная версия для вызова из других мест (синхронная, но оптимизированная)
    func generateRecurringTransactions() {
        // Используем кэшированные форматтеры
        let dateFormatter = Self.dateFormatter
        let timeFormatter = Self.timeFormatter

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
        let currentTime = timeFormatter.string(from: Date())
        
        // Автоматически выполняем recurring операции, срок которых наступил
        var hasChanges = false
        for i in allTransactions.indices {
            let transaction = allTransactions[i]
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate < today {
                // Срок наступил - помечаем как выполненную (убираем recurringSeriesId)
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    time: transaction.time,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: transaction.category,
                    subcategory: transaction.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: nil, // Убираем связь с recurring
                    recurringOccurrenceId: nil
                )
                allTransactions[i] = updatedTransaction
                hasChanges = true
            }
        }
        
        for series in recurringSeries where series.isActive {
            guard let startDate = dateFormatter.date(from: series.startDate) else { continue }
            
            // Генерируем транзакции на горизонт 12 месяцев
            var currentDate = startDate
            
            while currentDate <= horizonDate {
                let dateString = dateFormatter.string(from: currentDate)
                let occurrenceKey = "\(series.id):\(dateString)"
                
                // Быстрая проверка через Set
                if !existingOccurrenceKeys.contains(occurrenceKey) {
                    let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
                    
                    let transactionId = TransactionIDGenerator.generateID(
                        date: dateString,
                        description: series.description,
                        amount: amountDouble,
                        type: .expense,
                        currency: series.currency
                    )
                    
                    // Проверяем, нет ли уже такой транзакции
                    if !existingTransactionIds.contains(transactionId) {
                        let occurrenceId = UUID().uuidString
                        
                        let transaction = Transaction(
                            id: transactionId,
                            date: dateString,
                            time: currentTime,
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
                            recurringOccurrenceId: occurrenceId
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
            allTransactions.append(contentsOf: newTransactions)
            allTransactions.sort { $0.date > $1.date }
            recurringOccurrences.append(contentsOf: newOccurrences)
            recalculateAccountBalances()
            saveToStorage()
        } else if hasChanges {
            // Если были изменения в recurring (автоматическое выполнение), пересчитываем балансы и сохраняем
            recalculateAccountBalances()
            saveToStorage()
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
                        time: updatedTransaction.time,
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
                        recurringOccurrenceId: updatedTransaction.recurringOccurrenceId
                    )
                    allTransactions[index] = updatedTransaction
                }
            }
        }
        
        saveToStorage()
    }
    
    // MARK: - Subcategories
    
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
    
    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        categorySubcategoryLinks.removeAll { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        saveToStorage()
    }
    
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
    
    // Инвалидация кешей при изменении данных
    private func invalidateCaches() {
        summaryCacheInvalidated = true
        categoryExpensesCacheInvalidated = true
    }
}

// DateFilter удален - теперь используется TimeFilterManager

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
