//
//  CategoryAggregate.swift
//  AIFinanceManager
//
//  Created on 2026
//

import Foundation

/// In-memory модель агрегированных данных по категориям/подкатегориям
struct CategoryAggregate: Identifiable, Equatable {
    let id: String // Формат: "{category}_{subcategory}_{year}_{month}"
    let categoryName: String
    let subcategoryName: String? // nil для агрегата категории без подкатегории
    let year: Int16 // 0 = all-time
    let month: Int16 // 0 = yearly или all-time
    let totalAmount: Double // В базовой валюте
    let transactionCount: Int32
    let currency: String // Базовая валюта для агрегата
    let lastUpdated: Date
    let lastTransactionDate: Date?

    init(
        categoryName: String,
        subcategoryName: String? = nil,
        year: Int16,
        month: Int16,
        totalAmount: Double,
        transactionCount: Int32,
        currency: String,
        lastUpdated: Date = Date(),
        lastTransactionDate: Date? = nil
    ) {
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.year = year
        self.month = month
        self.totalAmount = totalAmount
        self.transactionCount = transactionCount
        self.currency = currency
        self.lastUpdated = lastUpdated
        self.lastTransactionDate = lastTransactionDate

        // Генерация ID
        let subcatPart = subcategoryName ?? ""
        self.id = "\(categoryName)_\(subcatPart)_\(year)_\(month)"
    }

    /// Создать ID для поиска агрегата
    static func makeId(
        category: String,
        subcategory: String? = nil,
        year: Int16,
        month: Int16
    ) -> String {
        let subcatPart = subcategory ?? ""
        return "\(category)_\(subcatPart)_\(year)_\(month)"
    }
}
