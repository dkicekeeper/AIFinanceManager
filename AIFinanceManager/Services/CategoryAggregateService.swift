//
//  CategoryAggregateService.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Сервис для построения и обновления агрегатов по категориям/подкатегориям

import Foundation

/// Сервис для работы с агрегатами категорий
class CategoryAggregateService {

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Build Aggregates

    /// Построить все агрегаты с нуля из транзакций
    /// - Parameters:
    ///   - transactions: Массив всех транзакций
    ///   - baseCurrency: Базовая валюта для конвертации
    /// - Returns: Массив агрегатов (месячные, годовые, all-time)
    func buildAggregates(from transactions: [Transaction], baseCurrency: String) -> [CategoryAggregate] {
        var aggregates: [String: CategoryAggregate] = [:]

        for transaction in transactions {
            guard transaction.type == .expense else { continue }

            // Парсим дату транзакции
            guard let date = dateFormatter.date(from: transaction.date) else { continue }
            let components = Calendar.current.dateComponents([.year, .month], from: date)
            guard let year = components.year, let month = components.month else { continue }

            let category = transaction.category.isEmpty ? String(localized: "category.uncategorized") : transaction.category
            let amount = transaction.convertedAmount ?? transaction.amount

            // Создаем агрегаты для категории (без подкатегории)
            updateAggregate(
                in: &aggregates,
                category: category,
                subcategory: nil,
                year: Int16(year),
                month: Int16(month),
                amount: amount,
                baseCurrency: baseCurrency,
                transactionDate: date
            )

            // Создаем агрегаты для подкатегории если есть
            if let subcategory = transaction.subcategory {
                updateAggregate(
                    in: &aggregates,
                    category: category,
                    subcategory: subcategory,
                    year: Int16(year),
                    month: Int16(month),
                    amount: amount,
                    baseCurrency: baseCurrency,
                    transactionDate: date
                )
            }
        }

        return Array(aggregates.values)
    }

    // MARK: - Incremental Updates

    /// Инкрементальное обновление при добавлении транзакции
    func updateAggregatesForAddition(
        transaction: Transaction,
        baseCurrency: String
    ) -> [CategoryAggregate] {
        guard transaction.type == .expense else { return [] }

        guard let date = dateFormatter.date(from: transaction.date) else { return [] }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return [] }

        let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category
        let amount = transaction.convertedAmount ?? transaction.amount

        var aggregates: [String: CategoryAggregate] = [:]

        // Обновляем агрегаты для категории
        updateAggregate(
            in: &aggregates,
            category: category,
            subcategory: nil,
            year: Int16(year),
            month: Int16(month),
            amount: amount,
            baseCurrency: baseCurrency,
            transactionDate: date
        )

        // Обновляем агрегаты для подкатегории если есть
        if let subcategory = transaction.subcategory {
            updateAggregate(
                in: &aggregates,
                category: category,
                subcategory: subcategory,
                year: Int16(year),
                month: Int16(month),
                amount: amount,
                baseCurrency: baseCurrency,
                transactionDate: date
            )
        }

        return Array(aggregates.values)
    }

    /// Инкрементальное обновление при удалении транзакции
    func updateAggregatesForDeletion(
        transaction: Transaction,
        baseCurrency: String
    ) -> [CategoryAggregate] {
        guard transaction.type == .expense else { return [] }

        guard let date = dateFormatter.date(from: transaction.date) else { return [] }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return [] }

        let category = transaction.category.isEmpty ? "Uncategorized" : transaction.category
        let amount = -(transaction.convertedAmount ?? transaction.amount) // Вычитаем сумму

        var aggregates: [String: CategoryAggregate] = [:]

        // Обновляем агрегаты для категории
        updateAggregate(
            in: &aggregates,
            category: category,
            subcategory: nil,
            year: Int16(year),
            month: Int16(month),
            amount: amount,
            baseCurrency: baseCurrency,
            transactionDate: date
        )

        // Обновляем агрегаты для подкатегории если есть
        if let subcategory = transaction.subcategory {
            updateAggregate(
                in: &aggregates,
                category: category,
                subcategory: subcategory,
                year: Int16(year),
                month: Int16(month),
                amount: amount,
                baseCurrency: baseCurrency,
                transactionDate: date
            )
        }

        return Array(aggregates.values)
    }

    /// Инкрементальное обновление при изменении транзакции
    func updateAggregatesForUpdate(
        oldTransaction: Transaction,
        newTransaction: Transaction,
        baseCurrency: String
    ) -> [CategoryAggregate] {
        // Удаляем старую транзакцию и добавляем новую
        let deletionAggregates = updateAggregatesForDeletion(
            transaction: oldTransaction,
            baseCurrency: baseCurrency
        )

        let additionAggregates = updateAggregatesForAddition(
            transaction: newTransaction,
            baseCurrency: baseCurrency
        )

        // Объединяем агрегаты
        var combined: [String: CategoryAggregate] = [:]
        for aggregate in deletionAggregates {
            combined[aggregate.id] = aggregate
        }
        for aggregate in additionAggregates {
            combined[aggregate.id] = aggregate
        }

        return Array(combined.values)
    }

    // MARK: - Private Helpers

    /// Обновить агрегат (создает daily (last 90 days), месячный, годовой и all-time)
    private func updateAggregate(
        in aggregates: inout [String: CategoryAggregate],
        category: String,
        subcategory: String?,
        year: Int16,
        month: Int16,
        amount: Double,
        baseCurrency: String,
        transactionDate: Date
    ) {
        // 0. Daily агрегат (только для последних 90 дней)
        let calendar = Calendar.current
        let daysAgo = calendar.dateComponents([.day], from: transactionDate, to: Date()).day ?? 0

        if daysAgo >= 0 && daysAgo <= 90 {
            // Создаём daily aggregate для последних 90 дней
            let day = Int16(calendar.component(.day, from: transactionDate))

            let dailyId = CategoryAggregate.makeId(
                category: category,
                subcategory: subcategory,
                year: year,
                month: month,
                day: day
            )

            if let existing = aggregates[dailyId] {
                aggregates[dailyId] = CategoryAggregate(
                    categoryName: category,
                    subcategoryName: subcategory,
                    year: year,
                    month: month,
                    day: day,
                    totalAmount: existing.totalAmount + amount,
                    transactionCount: existing.transactionCount + 1,
                    currency: baseCurrency,
                    lastUpdated: Date(),
                    lastTransactionDate: max(existing.lastTransactionDate ?? transactionDate, transactionDate)
                )
            } else {
                aggregates[dailyId] = CategoryAggregate(
                    categoryName: category,
                    subcategoryName: subcategory,
                    year: year,
                    month: month,
                    day: day,
                    totalAmount: amount,
                    transactionCount: 1,
                    currency: baseCurrency,
                    lastUpdated: Date(),
                    lastTransactionDate: transactionDate
                )
            }
        }

        // 1. Месячный агрегат
        let monthlyId = CategoryAggregate.makeId(
            category: category,
            subcategory: subcategory,
            year: year,
            month: month
        )

        if let existing = aggregates[monthlyId] {
            aggregates[monthlyId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: year,
                month: month,
                totalAmount: existing.totalAmount + amount,
                transactionCount: existing.transactionCount + 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: max(existing.lastTransactionDate ?? transactionDate, transactionDate)
            )
        } else {
            aggregates[monthlyId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: year,
                month: month,
                totalAmount: amount,
                transactionCount: 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: transactionDate
            )
        }

        // 2. Годовой агрегат
        let yearlyId = CategoryAggregate.makeId(
            category: category,
            subcategory: subcategory,
            year: year,
            month: 0
        )

        if let existing = aggregates[yearlyId] {
            aggregates[yearlyId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: year,
                month: 0,
                totalAmount: existing.totalAmount + amount,
                transactionCount: existing.transactionCount + 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: max(existing.lastTransactionDate ?? transactionDate, transactionDate)
            )
        } else {
            aggregates[yearlyId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: year,
                month: 0,
                totalAmount: amount,
                transactionCount: 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: transactionDate
            )
        }

        // 3. All-time агрегат
        let allTimeId = CategoryAggregate.makeId(
            category: category,
            subcategory: subcategory,
            year: 0,
            month: 0
        )

        if let existing = aggregates[allTimeId] {
            aggregates[allTimeId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: 0,
                month: 0,
                totalAmount: existing.totalAmount + amount,
                transactionCount: existing.transactionCount + 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: max(existing.lastTransactionDate ?? transactionDate, transactionDate)
            )
        } else {
            aggregates[allTimeId] = CategoryAggregate(
                categoryName: category,
                subcategoryName: subcategory,
                year: 0,
                month: 0,
                totalAmount: amount,
                transactionCount: 1,
                currency: baseCurrency,
                lastUpdated: Date(),
                lastTransactionDate: transactionDate
            )
        }
    }
}
