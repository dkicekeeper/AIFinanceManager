//
//  CSVImportService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Transaction Fingerprint

/// Fingerprint for detecting duplicate transactions
/// Uses normalized values for reliable duplicate detection
struct TransactionFingerprint: Hashable {
    let date: String
    let amount: Double
    let description: String
    let accountId: String
    let type: String
    
    init(from transaction: Transaction) {
        self.date = transaction.date
        self.amount = transaction.amount
        // Normalize description: lowercase, trim, remove extra spaces
        self.description = transaction.description
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        self.accountId = transaction.accountId ?? ""
        self.type = transaction.type.rawValue
    }
    
    /// Create fingerprint from raw CSV data
    init(date: String, amount: Double, description: String, accountId: String?, type: TransactionType) {
        self.date = date
        self.amount = amount
        self.description = description
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        self.accountId = accountId ?? ""
        self.type = type.rawValue
    }
}

class CSVImportService {
    static func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel? = nil,
        progressCallback: ((Double) -> Void)? = nil
    ) async -> ImportResult {
        var importedCount = 0
        var skippedCount = 0
        var duplicatesSkipped = 0 // Дубликаты (по fingerprint)
        var createdAccounts = 0 // Создание счетов при импорте
        var createdCategories = 0
        var createdSubcategories = 0
        var errors: [String] = []
        
        let totalRows = csvFile.rows.count
        
        // Build fingerprint set of existing transactions for duplicate detection
        print("🔍 [CSV_IMPORT] Building fingerprint set from existing transactions")
        let existingFingerprints = await MainActor.run {
            Set(transactionsViewModel.allTransactions.map { TransactionFingerprint(from: $0) })
        }
        print("🔍 [CSV_IMPORT] Found \(existingFingerprints.count) existing transaction fingerprints")
        
        // Получаем индексы колонок
        let dateIndex = columnMapping.dateColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let typeIndex = columnMapping.typeColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let amountIndex = columnMapping.amountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let currencyIndex = columnMapping.currencyColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let accountIndex = columnMapping.accountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let targetAccountIndex = columnMapping.targetAccountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let targetCurrencyIndex = columnMapping.targetCurrencyColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let targetAmountIndex = columnMapping.targetAmountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let categoryIndex = columnMapping.categoryColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let subcategoriesIndex = columnMapping.subcategoriesColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let noteIndex = columnMapping.noteColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        
        guard let dateIdx = dateIndex,
              let typeIdx = typeIndex,
              let amountIdx = amountIndex else {
            return ImportResult(
                importedCount: 0,
                skippedCount: csvFile.rowCount,
                duplicatesSkipped: 0,
                createdAccounts: 0,
                createdCategories: 0,
                createdSubcategories: 0,
                errors: ["Не указаны обязательные колонки"]
            )
        }
        
        // Синхронизируем счета перед началом импорта
        await MainActor.run {
            if let accountsVM = accountsViewModel {
                transactionsViewModel.accounts = accountsVM.accounts
            }
            
            // Start batch mode to defer expensive operations until end
            print("📦 [CSV_IMPORT] Starting batch mode for performance")
            transactionsViewModel.beginBatch()
        }
        
        // Батчинг для экономии памяти: обрабатываем транзакции порциями
        let batchSize = 100 // Уменьшен размер батча для экономии памяти
        var transactionsBatch: [Transaction] = []
        var transactionSubcategoryLinksBatch: [String: [String]] = [:]
        var allTransactionSubcategoryLinks: [String: [String]] = [:] // Накапливаем все связи для сохранения в конце
        
        // Словарь для отслеживания созданных счетов во время импорта (чтобы избежать дублей)
        var createdAccountsDuringImport: [String: String] = [:] // [accountName.lowercased(): accountId]
        
        // Функция для поиска счета по имени (case-insensitive)
        func findAccount(by name: String, in accountsVM: AccountsViewModel?, in transactionsVM: TransactionsViewModel) -> Account? {
            let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()
            
            // Проверяем в созданных во время импорта (самый быстрый способ)
            if let accountId = createdAccountsDuringImport[normalizedName],
               let accountsVM = accountsVM {
                return accountsVM.accounts.first(where: { $0.id == accountId })
            }
            
            // Сначала проверяем в accountsViewModel
            if let accountsVM = accountsVM {
                if let account = accountsVM.accounts.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName }) {
                    // Сохраняем в кэш для быстрого поиска
                    createdAccountsDuringImport[normalizedName] = account.id
                    return account
                }
            }
            
            // Затем проверяем в transactionsViewModel
            if let account = transactionsVM.accounts.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName }) {
                // Сохраняем в кэш для быстрого поиска
                createdAccountsDuringImport[normalizedName] = account.id
                return account
            }
            
            return nil
        }
        
        func processBatch() async {
            guard !transactionsBatch.isEmpty else { return }
            
            await MainActor.run {
                // Синхронизируем счета из accountsViewModel в transactionsViewModel (на случай создания новых)
                if let accountsVM = accountsViewModel {
                    transactionsViewModel.accounts = accountsVM.accounts
                }
                
                // Добавляем транзакции БЕЗ сохранения и пересчета балансов
                transactionsViewModel.addTransactionsForImport(transactionsBatch)
                
                // Накапливаем связи для сохранения в конце
                allTransactionSubcategoryLinks.merge(transactionSubcategoryLinksBatch) { (_, new) in new }
            }
            
            // Очищаем батч для освобождения памяти
            transactionsBatch.removeAll(keepingCapacity: false)
            transactionSubcategoryLinksBatch.removeAll(keepingCapacity: false)
            
            // Принудительная очистка памяти
            autoreleasepool {}
        }
        
        for (rowIndex, row) in csvFile.rows.enumerated() {
            // Обновляем прогресс
            if let progressCallback = progressCallback, totalRows > 0 {
                let progress = Double(rowIndex) / Double(totalRows)
                await MainActor.run {
                    progressCallback(progress)
                }
            }
            
            // Парсим дату
            guard let dateString = row[safe: dateIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
                  !dateString.isEmpty,
                  let date = parseDate(dateString, format: columnMapping.dateFormat) else {
                skippedCount += 1
                errors.append("Строка \(rowIndex + 2): неверная дата")
                continue
            }
            
            // Парсим тип
            guard let typeString = row[safe: typeIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
                  !typeString.isEmpty,
                  let type = parseType(typeString, mappings: columnMapping.typeMappings) else {
                skippedCount += 1
                errors.append("Строка \(rowIndex + 2): неверный тип операции")
                continue
            }
            
            // Парсим сумму
            guard let amountString = row[safe: amountIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
                  !amountString.isEmpty,
                  let amount = parseAmount(amountString) else {
                skippedCount += 1
                errors.append("Строка \(rowIndex + 2): неверная сумма")
                continue
            }
            
            // Парсим валюту
            let currency = currencyIndex.flatMap { row[safe: $0]?.trimmingCharacters(in: CharacterSet.whitespaces) } ?? "KZT"
            
            // ===== ПРИМЕНЯЕМ ПРАВИЛА ПАРСИНГА В ЗАВИСИМОСТИ ОТ ТИПА ОПЕРАЦИИ =====
            // 1. Расход: счет = счет, категория = категория расхода (стандартное поведение)
            // 2. Доход: счет = категория дохода, категория = счет пополнения (меняем местами)
            // 3. Перевод: счет = счет, категория = счет получателя
            
            // Получаем сырые значения из CSV
            let rawAccountValue = accountIndex.flatMap { row[safe: $0]?.trimmingCharacters(in: CharacterSet.whitespaces) } ?? ""
            let rawCategoryValue = categoryIndex.flatMap { row[safe: $0]?.trimmingCharacters(in: CharacterSet.whitespaces) } ?? ""
            let rawTargetAccountValue = targetAccountIndex.flatMap { row[safe: $0]?.trimmingCharacters(in: CharacterSet.whitespaces) } ?? ""
            
            // Применяем правила парсинга в зависимости от типа
            let effectiveAccountValue: String
            let effectiveCategoryValue: String
            
            switch type {
            case .expense:
                // Расход: счет = счет, категория = категория расхода
                effectiveAccountValue = rawAccountValue
                effectiveCategoryValue = rawCategoryValue
            case .income:
                // Доход: колонка "счет" = категория дохода, колонка "счет получателя" = счет пополнения
                // Поэтому: счет транзакции = счет получателя, категория транзакции = счет (категория дохода)
                effectiveAccountValue = rawTargetAccountValue
                effectiveCategoryValue = rawAccountValue
            case .internalTransfer:
                // Перевод: счет = счет, категория всегда "Перевод" (локализованная)
                effectiveAccountValue = rawAccountValue
                effectiveCategoryValue = "" // Будет использована дефолтная категория "Перевод"
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Депозитные операции: стандартное поведение (как расход)
                effectiveAccountValue = rawAccountValue
                effectiveCategoryValue = rawCategoryValue
            }
            
            // Парсим счет с учетом примененных правил
            var accountId: String? = nil
            
            // "Другое" — зарезервированное имя категории по умолчанию, никогда не создаём счёт с таким именем
            let reservedCategoryNames = ["другое", "other"]
            let isReservedCategoryName = reservedCategoryNames.contains(effectiveAccountValue.trimmingCharacters(in: .whitespaces).lowercased())
            
            if !effectiveAccountValue.isEmpty, !isReservedCategoryName {
                let normalizedAccountName = effectiveAccountValue.lowercased()
                
                // Сначала проверяем маппинг
                if let mappedAccountId = entityMapping.accountMappings[effectiveAccountValue] {
                    accountId = mappedAccountId
                } else if let account = findAccount(by: effectiveAccountValue, in: accountsViewModel, in: transactionsViewModel) {
                    // Счет уже существует - используем его для всех типов транзакций
                    accountId = account.id
                    createdAccountsDuringImport[normalizedAccountName] = account.id
                } else if let accountsVM = accountsViewModel {
                    // Автоматически создаем счет
                    await MainActor.run {
                        // Проверяем еще раз перед созданием (на случай параллельного создания)
                        if let existingAccount = findAccount(by: effectiveAccountValue, in: accountsVM, in: transactionsViewModel) {
                            accountId = existingAccount.id
                            createdAccountsDuringImport[normalizedAccountName] = existingAccount.id
                        } else {
                            accountsVM.addAccount(
                                name: effectiveAccountValue,
                                balance: 0.0,
                                currency: currency,
                                bankLogo: .none
                            )
                            createdAccounts += 1
                            
                            // Получаем ID только что созданного счета
                            if let newAccount = accountsVM.accounts.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedAccountName }) {
                                accountId = newAccount.id
                                createdAccountsDuringImport[normalizedAccountName] = newAccount.id
                            }
                        }
                    }
                }
            }
            
            // Парсим валюту счета получателя (делаем это до парсинга счета получателя, чтобы использовать при создании)
            var targetCurrency: String? = nil
            if let targetCurrencyIdx = targetCurrencyIndex,
               let targetCurrencyValue = row[safe: targetCurrencyIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !targetCurrencyValue.isEmpty {
                targetCurrency = targetCurrencyValue
            }
            
            // Парсим счет получателя (только для переводов, не для доходов)
            var targetAccountId: String? = nil
            let targetAccountCurrency = targetCurrency ?? currency // Используем валюту получателя или валюту операции
            
            // Для доходов не используем targetAccountId - счет указан в accountId
            if type != .income, let targetAccountIdx = targetAccountIndex,
               let targetAccountValue = row[safe: targetAccountIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !targetAccountValue.isEmpty {
                let normalizedTargetAccountName = targetAccountValue.lowercased()
                
                // Сначала проверяем маппинг
                if let mappedAccountId = entityMapping.accountMappings[targetAccountValue] {
                    targetAccountId = mappedAccountId
                } else if let account = findAccount(by: targetAccountValue, in: accountsViewModel, in: transactionsViewModel) {
                    // Счет уже существует
                    targetAccountId = account.id
                    // Сохраняем в словарь для быстрого поиска
                    createdAccountsDuringImport[normalizedTargetAccountName] = account.id
                } else if let accountsVM = accountsViewModel {
                    // Автоматически создаем счет получателя, если не выбран в маппинге
                    await MainActor.run {
                        // Проверяем еще раз перед созданием (на случай параллельного создания)
                        if let existingAccount = findAccount(by: targetAccountValue, in: accountsVM, in: transactionsViewModel) {
                            targetAccountId = existingAccount.id
                            createdAccountsDuringImport[normalizedTargetAccountName] = existingAccount.id
                        } else {
                            accountsVM.addAccount(
                                name: targetAccountValue,
                                balance: 0.0,
                                currency: targetAccountCurrency,
                                bankLogo: .none
                            )
                            createdAccounts += 1
                            
                            // Получаем ID только что созданного счета
                            if let newAccount = accountsVM.accounts.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedTargetAccountName }) {
                                targetAccountId = newAccount.id
                                createdAccountsDuringImport[normalizedTargetAccountName] = newAccount.id
                            }
                        }
                    }
                }
            }
            
            // Парсим сумму счета получателя
            var targetAmount: Double? = nil
            if let targetAmountIdx = targetAmountIndex,
               let targetAmountString = row[safe: targetAmountIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !targetAmountString.isEmpty,
               let parsedTargetAmount = parseAmount(targetAmountString) {
                targetAmount = parsedTargetAmount
            }
            
            // Парсим категорию с учетом примененных правил парсинга
            // Для переводов используем локализованное название "Перевод", для остальных - "Другое"
            var categoryName = type == .internalTransfer ? String(localized: "transactionForm.transfer") : "Другое"
            var categoryId: String? = nil
            
            // Используем effectiveCategoryValue (с учетом правил парсинга по типу операции)
            if !effectiveCategoryValue.isEmpty {
                if let mappedCategory = entityMapping.categoryMappings[effectiveCategoryValue] {
                    categoryName = mappedCategory
                    // Находим ID категории по имени
                    if let existingCategory = categoriesViewModel.customCategories.first(where: { $0.name == mappedCategory && $0.type == type }) {
                        categoryId = existingCategory.id
                    } else {
                        // Категория из маппинга не существует - создаем её
                        let iconName = CategoryIcon.iconName(for: mappedCategory, type: type, customCategories: categoriesViewModel.customCategories)
                        let colorHex = CategoryColors.hexColor(for: mappedCategory, customCategories: categoriesViewModel.customCategories)
                        let hexString = colorToHex(colorHex)
                        
                        let newCategory = CustomCategory(
                            name: mappedCategory,
                            iconName: iconName,
                            colorHex: hexString,
                            type: type
                        )
                        // Добавляем напрямую в массив, чтобы избежать async сохранения во время импорта
                        categoriesViewModel.customCategories.append(newCategory)
                        categoryId = newCategory.id
                        createdCategories += 1
                    }
                } else if let existingCategory = categoriesViewModel.customCategories.first(where: { $0.name == effectiveCategoryValue && $0.type == type }) {
                    categoryName = effectiveCategoryValue
                    categoryId = existingCategory.id
                } else {
                    // Создаем категорию с автоматическим подбором иконки и цвета
                    let iconName = CategoryIcon.iconName(for: effectiveCategoryValue, type: type, customCategories: categoriesViewModel.customCategories)
                    let colorHex = CategoryColors.hexColor(for: effectiveCategoryValue, customCategories: categoriesViewModel.customCategories)
                    // Конвертируем Color в hex строку
                    let hexString = colorToHex(colorHex)
                    
                    let newCategory = CustomCategory(
                        name: effectiveCategoryValue,
                        iconName: iconName,
                        colorHex: hexString,
                        type: type
                    )
                    // Добавляем напрямую в массив, чтобы избежать async сохранения во время импорта
                    categoriesViewModel.customCategories.append(newCategory)
                    categoryName = effectiveCategoryValue
                    categoryId = newCategory.id
                    createdCategories += 1
                }
            }
            
            // Если categoryId все еще nil (категория не указана), находим или создаем дефолтную категорию
            if categoryId == nil {
                // Ищем дефолтную категорию для данного типа транзакции
                if let defaultCategory = categoriesViewModel.customCategories.first(where: { $0.name == categoryName && $0.type == type }) {
                    categoryId = defaultCategory.id
                } else {
                    // Создаем дефолтную категорию если её нет
                    // Для переводов это "Перевод", для остальных - "Другое"
                    let iconName = CategoryIcon.iconName(for: categoryName, type: type, customCategories: categoriesViewModel.customCategories)
                    let colorHex = CategoryColors.hexColor(for: categoryName, customCategories: categoriesViewModel.customCategories)
                    let hexString = colorToHex(colorHex)
                    
                    let defaultCategory = CustomCategory(
                        name: categoryName,
                        iconName: iconName,
                        colorHex: hexString,
                        type: type
                    )
                    // Добавляем напрямую в массив, чтобы избежать async сохранения во время импорта
                    categoriesViewModel.customCategories.append(defaultCategory)
                    categoryId = defaultCategory.id
                    createdCategories += 1
                }
            }
            
            // Парсим подкатегории
            var subcategoryName: String? = nil
            var subcategoryIds: [String] = []
            if let subcategoriesIdx = subcategoriesIndex,
               let subcategoriesValue = row[safe: subcategoriesIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !subcategoriesValue.isEmpty {
                let subcategories = subcategoriesValue.components(separatedBy: columnMapping.subcategoriesSeparator)
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    .filter { !$0.isEmpty }
                
                // Создаем и привязываем подкатегории (CategoriesViewModel требует MainActor)
                if let catId = categoryId {
                    let (newSubcategoryIds, newCreatedCount) = await MainActor.run { () -> ([String], Int) in
                        var ids: [String] = []
                        var created = 0
                        
                        for subcategoryNameValue in subcategories {
                            // Проверяем, существует ли уже такая подкатегория
                            let existingSubcategory = categoriesViewModel.subcategories.first { $0.name.lowercased() == subcategoryNameValue.lowercased() }
                            
                            let subcategory: Subcategory
                            if let existing = existingSubcategory {
                                subcategory = existing
                            } else {
                                // Создаем новую подкатегорию
                                subcategory = categoriesViewModel.addSubcategory(name: subcategoryNameValue)
                                created += 1
                            }
                            
                            // Привязываем подкатегорию к категории без немедленного сохранения
                            // (сохранение будет выполнено в конце через saveAllData())
                            categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(subcategoryId: subcategory.id, categoryId: catId)
                            ids.append(subcategory.id)
                        }
                        
                        return (ids, created)
                    }
                    
                    subcategoryIds = newSubcategoryIds
                    createdSubcategories += newCreatedCount
                }
                
                // Используем первую подкатегорию для обратной совместимости с полем subcategory
                if let firstSubcategory = subcategories.first {
                    subcategoryName = firstSubcategory
                }
            }
            
            // Парсим заметку
            let note = noteIndex.flatMap { row[safe: $0]?.trimmingCharacters(in: CharacterSet.whitespaces) } ?? ""
            
            // Создаем транзакцию
            let transactionDateFormatter = DateFormatters.dateFormatter
            let transactionDateString = transactionDateFormatter.string(from: date)
            
            // Для CSV импорта используем дату транзакции как createdAt (чтобы сортировка соответствовала дате)
            // Но добавляем небольшое смещение на основе индекса строки для сохранения порядка внутри дня
            let createdAt = date.timeIntervalSince1970 + Double(rowIndex) * 0.001 // 1ms на транзакцию для сохранения порядка
            
            // Генерируем ID для транзакции (используем note, даже если пустое)
            // Включаем createdAt в генерацию ID для уникальности
            let descriptionForID = note.isEmpty ? categoryName : note
            let transactionId = TransactionIDGenerator.generateID(
                date: transactionDateString,
                description: descriptionForID,
                amount: amount,
                type: type,
                currency: currency,
                createdAt: createdAt
            )
            
            let transaction = Transaction(
                id: transactionId,
                date: transactionDateString,
                description: note, // Оставляем пустым, если пустое
                amount: amount,
                currency: currency,
                convertedAmount: nil, // Конвертация будет выполнена позже, если нужно
                type: type,
                category: categoryName,
                subcategory: subcategoryName,
                accountId: accountId,
                targetAccountId: targetAccountId,
                targetCurrency: targetCurrency,
                targetAmount: targetAmount,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: createdAt // Используем дату транзакции + небольшое смещение для сохранения порядка
            )
            
            // Check for duplicates using fingerprint
            let fingerprint = TransactionFingerprint(from: transaction)
            if existingFingerprints.contains(fingerprint) {
                duplicatesSkipped += 1
                skippedCount += 1
                print("⏭️ [CSV_IMPORT] Row \(rowIndex + 2): Duplicate detected (fingerprint match), skipping")
                continue
            }
            
            transactionsBatch.append(transaction)
            
            // Накапливаем связи подкатегорий с транзакцией для текущего батча
            if !subcategoryIds.isEmpty {
                transactionSubcategoryLinksBatch[transactionId] = subcategoryIds
            }
            
            importedCount += 1
            
            // Обрабатываем батч, если достигли размера батча или это последняя строка
            if transactionsBatch.count >= batchSize || rowIndex == totalRows - 1 {
                await processBatch()
            }
        }
        
        // Обновляем прогресс до 100%
        if let progressCallback = progressCallback {
            await MainActor.run {
                progressCallback(1.0)
            }
        }
        
        // Финальная обработка: сохраняем все связи и пересчитываем балансы
        await MainActor.run {
            // Синхронизируем счета из accountsViewModel в transactionsViewModel
            if let accountsVM = accountsViewModel {
                transactionsViewModel.accounts = accountsVM.accounts
            }
            
            // Сохраняем все связи транзакций с подкатегориями одним батчем
            if !allTransactionSubcategoryLinks.isEmpty {
                categoriesViewModel.batchLinkSubcategoriesToTransaction(allTransactionSubcategoryLinks)
            }
            
            // Синхронизируем категории, подкатегории и связи из CategoriesViewModel в TransactionsViewModel
            // перед сохранением, чтобы TransactionsViewModel.saveToStorage() не перезаписал устаревшие данные
            transactionsViewModel.customCategories = categoriesViewModel.customCategories
            transactionsViewModel.subcategories = categoriesViewModel.subcategories
            transactionsViewModel.categorySubcategoryLinks = categoriesViewModel.categorySubcategoryLinks
            transactionsViewModel.transactionSubcategoryLinks = categoriesViewModel.transactionSubcategoryLinks
            
            // Явно сохраняем все данные CategoriesViewModel (подкатегории, связи и т.д.)
            // чтобы убедиться, что все данные сохранены после импорта
            categoriesViewModel.saveAllData()
            
            // End batch mode - this triggers balance recalculation and save
            print("📦 [CSV_IMPORT] Ending batch mode - triggering balance recalculation")
            transactionsViewModel.endBatch()
            
            // Note: endBatch() now handles:
            // - recalculateAccountBalances()
            // - saveToStorage()
            // But we still need to do some manual steps for CSV import

            // Перестраиваем индексы для быстрой фильтрации
            transactionsViewModel.rebuildIndexes()

            // Предварительно вычисляем конвертации валют в фоне для улучшения производительности UI
            transactionsViewModel.precomputeCurrencyConversions()

            // Синхронизируем обновленные балансы обратно в accountsViewModel и сохраняем их
            if let accountsVM = accountsViewModel {
                // Обновляем балансы в accountsViewModel на основе пересчитанных балансов
                for (index, account) in accountsVM.accounts.enumerated() {
                    if let updatedAccount = transactionsViewModel.accounts.first(where: { $0.id == account.id }) {
                        // Обновляем счет с новым балансом
                        accountsVM.accounts[index].balance = updatedAccount.balance
                        // Обновляем начальный баланс, чтобы он соответствовал текущему балансу после пересчета
                        accountsVM.setInitialBalance(updatedAccount.balance, for: account.id)
                    }
                }
                // Сохраняем обновленные балансы счетов одним батчем (синхронно для импорта)
                accountsVM.saveAllAccountsSync()
            }
            
            // Force save again to ensure everything is persisted (endBatch already saved, but sync is safer)
            transactionsViewModel.saveToStorageSync()
            
            // Принудительно уведомляем об изменении для обновления UI
            transactionsViewModel.objectWillChange.send()
            categoriesViewModel.objectWillChange.send()
            if let accountsVM = accountsViewModel {
                accountsVM.objectWillChange.send()
            }
        }
        
        // Очищаем накопленные данные
        allTransactionSubcategoryLinks.removeAll(keepingCapacity: false)
        
        // Log import summary
        print("📊 [CSV_IMPORT] Import completed:")
        print("   ✅ Imported: \(importedCount)")
        print("   ⏭️ Skipped: \(skippedCount - duplicatesSkipped)")
        print("   🔄 Duplicates: \(duplicatesSkipped)")
        print("   ➕ Accounts created: \(createdAccounts)")
        print("   ➕ Categories created: \(createdCategories)")
        print("   ➕ Subcategories created: \(createdSubcategories)")
        if !errors.isEmpty {
            print("   ⚠️ Errors: \(errors.count)")
        }
        
        return ImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            duplicatesSkipped: duplicatesSkipped,
            createdAccounts: createdAccounts,
            createdCategories: createdCategories,
            createdSubcategories: createdSubcategories,
            errors: errors
        )
    }
    
    private static func parseDate(_ dateString: String, format: DateFormatType) -> Date? {
        let formatter = DateFormatter()
        
        switch format {
        case .iso:
            formatter.dateFormat = "yyyy-MM-dd"
        case .ddmmyyyy:
            formatter.dateFormat = "dd.MM.yyyy"
        case .auto:
            // Пробуем разные форматы
            let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "MM/dd/yyyy"]
            for fmt in formats {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            return nil
        }
        
        return formatter.date(from: dateString)
    }
    
    private static func parseType(_ typeString: String, mappings: [String: TransactionType]) -> TransactionType? {
        let normalized = typeString.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Проверяем маппинг
        if let type = mappings[normalized] {
            return type
        }
        
        // Проверяем частичное совпадение
        for (key, type) in mappings {
            if normalized.contains(key) || key.contains(normalized) {
                return type
            }
        }
        
        return nil
    }
    
    private static func parseAmount(_ amountString: String) -> Double? {
        let cleaned = amountString
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return Double(cleaned)
    }
    
    // Конвертирует Color в hex строку
    private static func colorToHex(_ color: Color) -> String {
        // Получаем UIColor из SwiftUI Color
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
