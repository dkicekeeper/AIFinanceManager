//
//  CSVImportService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import UIKit

class CSVImportService {
    static func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        viewModel: TransactionsViewModel
    ) async -> ImportResult {
        var importedCount = 0
        var skippedCount = 0
        let createdAccounts = 0 // Создание счетов происходит в CSVEntityMappingView
        var createdCategories = 0
        var createdSubcategories = 0
        var errors: [String] = []
        
        // Получаем индексы колонок
        let dateIndex = columnMapping.dateColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let typeIndex = columnMapping.typeColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let amountIndex = columnMapping.amountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let currencyIndex = columnMapping.currencyColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
        let accountIndex = columnMapping.accountColumn.flatMap { csvFile.headers.firstIndex(of: $0) }
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
        
        var transactions: [Transaction] = []
        
        for (rowIndex, row) in csvFile.rows.enumerated() {
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
                if let mappedAccountId = entityMapping.accountMappings[accountValue] {
                    accountId = mappedAccountId
                } else if let account = viewModel.accounts.first(where: { $0.name == accountValue }) {
                    accountId = account.id
                }
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
                    categoryId = viewModel.customCategories.first(where: { $0.name == mappedCategory })?.id
                } else if let existingCategory = viewModel.customCategories.first(where: { $0.name == categoryValue }) {
                    categoryName = categoryValue
                    categoryId = existingCategory.id
                } else {
                    // Создаем категорию с автоматическим подбором иконки и цвета
                    let iconName = CategoryEmoji.iconName(for: categoryValue, type: type, customCategories: viewModel.customCategories)
                    let colorHex = CategoryColors.hexColor(for: categoryValue, customCategories: viewModel.customCategories)
                    // Конвертируем Color в hex строку
                    let hexString = colorToHex(colorHex)
                    
                    let newCategory = CustomCategory(
                        name: categoryValue,
                        iconName: iconName,
                        colorHex: hexString,
                        type: type
                    )
                    viewModel.addCategory(newCategory)
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
                        let existingSubcategory = viewModel.subcategories.first { $0.name.lowercased() == subcategoryNameValue.lowercased() }
                        
                        let subcategory: Subcategory
                        if let existing = existingSubcategory {
                            subcategory = existing
                        } else {
                            // Создаем новую подкатегорию
                            subcategory = viewModel.addSubcategory(name: subcategoryNameValue)
                            createdSubcategories += 1
                        }
                        
                        // Привязываем подкатегорию к категории, если еще не привязана
                        viewModel.linkSubcategoryToCategory(subcategoryId: subcategory.id, categoryId: catId)
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
            
            // Генерируем ID для транзакции (используем note, даже если пустое)
            let descriptionForID = note.isEmpty ? categoryName : note
            let transactionId = TransactionIDGenerator.generateID(
                date: transactionDateString,
                description: descriptionForID,
                amount: amount,
                type: type,
                currency: currency
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
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil
            )
            
            transactions.append(transaction)
            
            // Привязываем подкатегории к транзакции
            if !subcategoryIds.isEmpty {
                viewModel.linkSubcategoriesToTransaction(transactionId: transactionId, subcategoryIds: subcategoryIds)
            }
            
            importedCount += 1
        }
        
        // Добавляем транзакции батчами
        await MainActor.run {
            viewModel.addTransactions(transactions)
        }
        
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
