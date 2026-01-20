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
        var createdAccounts = 0 // Создание счетов при импорте
        var createdCategories = 0
        var createdSubcategories = 0
        var errors: [String] = []
        
        let totalRows = csvFile.rows.count
        
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
            
            // Парсим счет
            var accountId: String? = nil
            if let accountIdx = accountIndex,
               let accountValue = row[safe: accountIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !accountValue.isEmpty {
                let normalizedAccountName = accountValue.lowercased()
                
                // Сначала проверяем маппинг
                if let mappedAccountId = entityMapping.accountMappings[accountValue] {
                    accountId = mappedAccountId
                } else if let account = findAccount(by: accountValue, in: accountsViewModel, in: transactionsViewModel) {
                    // Счет уже существует
                    accountId = account.id
                    // Сохраняем в словарь для быстрого поиска
                    createdAccountsDuringImport[normalizedAccountName] = account.id
                } else if let accountsVM = accountsViewModel {
                    // Автоматически создаем счет, если не выбран в маппинге (как категории)
                    await MainActor.run {
                        // Проверяем еще раз перед созданием (на случай параллельного создания)
                        if let existingAccount = findAccount(by: accountValue, in: accountsVM, in: transactionsViewModel) {
                            accountId = existingAccount.id
                            createdAccountsDuringImport[normalizedAccountName] = existingAccount.id
                        } else {
                            accountsVM.addAccount(
                                name: accountValue,
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
            
            // Парсим счет получателя
            var targetAccountId: String? = nil
            let targetAccountCurrency = targetCurrency ?? currency // Используем валюту получателя или валюту операции
            if let targetAccountIdx = targetAccountIndex,
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
            
            // Парсим категорию
            var categoryName = "Другое"
            var categoryId: String? = nil
            if let categoryIdx = categoryIndex,
               let categoryValue = row[safe: categoryIdx]?.trimmingCharacters(in: CharacterSet.whitespaces),
               !categoryValue.isEmpty {
                if let mappedCategory = entityMapping.categoryMappings[categoryValue] {
                    categoryName = mappedCategory
                    // Находим ID категории по имени
                    categoryId = categoriesViewModel.customCategories.first(where: { $0.name == mappedCategory })?.id
                } else if let existingCategory = categoriesViewModel.customCategories.first(where: { $0.name == categoryValue }) {
                    categoryName = categoryValue
                    categoryId = existingCategory.id
                } else {
                    // Создаем категорию с автоматическим подбором иконки и цвета
                    let iconName = CategoryIcon.iconName(for: categoryValue, type: type, customCategories: categoriesViewModel.customCategories)
                    let colorHex = CategoryColors.hexColor(for: categoryValue, customCategories: categoriesViewModel.customCategories)
                    // Конвертируем Color в hex строку
                    let hexString = colorToHex(colorHex)
                    
                    let newCategory = CustomCategory(
                        name: categoryValue,
                        iconName: iconName,
                        colorHex: hexString,
                        type: type
                    )
                    categoriesViewModel.addCategory(newCategory)
                    categoryName = categoryValue
                    categoryId = newCategory.id
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
                
                // Создаем и привязываем подкатегории
                if let catId = categoryId {
                    for subcategoryNameValue in subcategories {
                        // Проверяем, существует ли уже такая подкатегория
                        let existingSubcategory = categoriesViewModel.subcategories.first { $0.name.lowercased() == subcategoryNameValue.lowercased() }
                        
                        let subcategory: Subcategory
                        if let existing = existingSubcategory {
                            subcategory = existing
                        } else {
                            // Создаем новую подкатегорию
                            subcategory = categoriesViewModel.addSubcategory(name: subcategoryNameValue)
                            createdSubcategories += 1
                        }
                        
                        // Привязываем подкатегорию к категории, если еще не привязана
                        categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategory.id, categoryId: catId)
                        subcategoryIds.append(subcategory.id)
                    }
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
            
            // Пересчитываем балансы один раз в конце
            transactionsViewModel.recalculateAccountBalances()
            
            // Сохраняем все данные один раз в конце
            transactionsViewModel.saveToStorage()
            
            // Принудительно уведомляем об изменении для обновления UI
            transactionsViewModel.objectWillChange.send()
            if let accountsVM = accountsViewModel {
                accountsVM.objectWillChange.send()
            }
        }
        
        // Очищаем накопленные данные
        allTransactionSubcategoryLinks.removeAll(keepingCapacity: false)
        
        return ImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
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
