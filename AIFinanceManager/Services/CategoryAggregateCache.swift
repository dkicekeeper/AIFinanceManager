//
//  CategoryAggregateCache.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  In-memory кеш для быстрого O(1) доступа к агрегатам категорий

import Foundation

/// In-memory кеш поверх CoreData агрегатов для быстрых чтений
@MainActor
class CategoryAggregateCache {

    // MARK: - Properties

    /// Кеш агрегатов по ID (формат: "{category}_{subcategory}_{year}_{month}")
    private var aggregatesByKey: [String: CategoryAggregate] = [:]

    /// Флаг загрузки из CoreData
    private var isLoaded = false

    private let service = CategoryAggregateService()

    // MARK: - Loading

    /// Загрузить агрегаты из CoreData при первом обращении
    func loadFromCoreData(repository: CoreDataRepository) async {
        guard !isLoaded else { return }

        // Загрузить из CoreData в фоновом потоке
        let aggregates = await Task.detached(priority: .userInitiated) {
            repository.loadAggregates()
        }.value

        // Обновить memory cache НА ГЛАВНОМ ПОТОКЕ
        await MainActor.run {
            self.aggregatesByKey.removeAll()
            for aggregate in aggregates {
                self.aggregatesByKey[aggregate.id] = aggregate
            }
            self.isLoaded = true
        }
    }

    // MARK: - Category Expenses

    /// Получить суммы по категориям для периода (O(1) для кешированных)
    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String
    ) -> [String: CategoryExpense] {

        var result: [String: CategoryExpense] = [:]

        // Определить диапазон года/месяца для фильтра
        let (targetYear, targetMonth) = getYearMonth(from: timeFilter)

        // Итерировать по агрегатам и фильтровать по периоду
        for (_, aggregate) in aggregatesByKey {
            // Пропустить агрегаты не в базовой валюте
            guard aggregate.currency == baseCurrency else { continue }

            // Фильтр по периоду
            let matches = matchesTimeFilter(
                aggregate: aggregate,
                targetYear: targetYear,
                targetMonth: targetMonth
            )

            guard matches else { continue }

            let category = aggregate.categoryName

            if let subcategoryName = aggregate.subcategoryName {
                // Это подкатегория - добавить к subcategories
                if var existing = result[category] {
                    existing.subcategories[subcategoryName, default: 0] += aggregate.totalAmount
                    result[category] = existing
                } else {
                    result[category] = CategoryExpense(
                        total: 0,
                        subcategories: [subcategoryName: aggregate.totalAmount]
                    )
                }
            } else {
                // Это категория - добавить к total
                if var existing = result[category] {
                    existing.total += aggregate.totalAmount
                    result[category] = existing
                } else {
                    result[category] = CategoryExpense(
                        total: aggregate.totalAmount,
                        subcategories: [:]
                    )
                }
            }
        }

        return result
    }

    /// Определить год/месяц из TimeFilter
    private func getYearMonth(from filter: TimeFilter) -> (year: Int16, month: Int16) {
        let calendar = Calendar.current
        let now = Date()

        switch filter.preset {
        case .allTime:
            return (0, 0) // all-time агрегаты

        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            return (Int16(components.year ?? 0), Int16(components.month ?? 0))

        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
                return (0, 0)
            }
            let components = calendar.dateComponents([.year, .month], from: lastMonth)
            return (Int16(components.year ?? 0), Int16(components.month ?? 0))

        case .thisYear:
            let components = calendar.dateComponents([.year], from: now)
            return (Int16(components.year ?? 0), 0) // годовой агрегат

        case .last30Days:
            // Для диапазонов дней используем все агрегаты и фильтруем по lastTransactionDate
            return (-1, -1) // специальный маркер для date-based фильтров

        case .today, .yesterday, .thisWeek, .lastYear, .custom:
            // Для других фильтров используем все агрегаты и фильтруем по lastTransactionDate
            return (-1, -1)
        }
    }

    /// Проверить соответствие агрегата периоду
    private func matchesTimeFilter(
        aggregate: CategoryAggregate,
        targetYear: Int16,
        targetMonth: Int16
    ) -> Bool {

        // All-time
        if targetYear == 0 && targetMonth == 0 {
            return aggregate.year == 0 && aggregate.month == 0
        }

        // Yearly
        if targetYear > 0 && targetMonth == 0 {
            return aggregate.year == targetYear && aggregate.month == 0
        }

        // Monthly
        if targetYear > 0 && targetMonth > 0 {
            return aggregate.year == targetYear && aggregate.month == targetMonth
        }

        // Date-based filters (last 30/90/365 days, custom)
        if targetYear == -1 && targetMonth == -1 {
            // Используем месячные агрегаты и фильтруем по lastTransactionDate
            // Эта логика будет дополнена при интеграции с реальным TimeFilter
            return aggregate.month > 0 // Используем месячные агрегаты
        }

        return false
    }

    // MARK: - Updates

    /// Обновить кеш при изменении транзакции (гранулярная инвалидация)
    func updateForTransaction(
        transaction: Transaction,
        operation: AggregateOperation,
        baseCurrency: String
    ) {

        let aggregates: [CategoryAggregate]

        switch operation {
        case .add:
            aggregates = service.updateAggregatesForAddition(
                transaction: transaction,
                baseCurrency: baseCurrency
            )

        case .delete:
            aggregates = service.updateAggregatesForDeletion(
                transaction: transaction,
                baseCurrency: baseCurrency
            )

        case .update(let oldTransaction):
            aggregates = service.updateAggregatesForUpdate(
                oldTransaction: oldTransaction,
                newTransaction: transaction,
                baseCurrency: baseCurrency
            )
        }

        // Обновить кеш
        for aggregate in aggregates {
            if let existing = aggregatesByKey[aggregate.id] {
                // Инкрементальное обновление существующего агрегата
                let updated = CategoryAggregate(
                    categoryName: aggregate.categoryName,
                    subcategoryName: aggregate.subcategoryName,
                    year: aggregate.year,
                    month: aggregate.month,
                    totalAmount: existing.totalAmount + aggregate.totalAmount,
                    transactionCount: existing.transactionCount + aggregate.transactionCount,
                    currency: baseCurrency,
                    lastUpdated: Date(),
                    lastTransactionDate: max(
                        existing.lastTransactionDate ?? aggregate.lastTransactionDate ?? Date(),
                        aggregate.lastTransactionDate ?? Date()
                    )
                )
                aggregatesByKey[aggregate.id] = updated
            } else {
                // Создать новый агрегат
                aggregatesByKey[aggregate.id] = aggregate
            }
        }
    }

    /// Инвалидировать конкретные категории
    func invalidateCategories(_ categoryNames: Set<String>) {
        // Удалить агрегаты затронутых категорий
        aggregatesByKey = aggregatesByKey.filter { _, aggregate in
            !categoryNames.contains(aggregate.categoryName)
        }
    }

    /// Полная перестройка кеша (смена валюты, миграция)
    func rebuildFromTransactions(
        _ transactions: [Transaction],
        baseCurrency: String,
        repository: CoreDataRepository
    ) async {

        // Построить агрегаты с нуля в фоновом потоке
        let aggregates: [CategoryAggregate] = await Task.detached(priority: .userInitiated) { [service] in
            service.buildAggregates(
                from: transactions,
                baseCurrency: baseCurrency
            )
        }.value

        // Обновить memory cache НА ГЛАВНОМ ПОТОКЕ
        await MainActor.run {
            self.aggregatesByKey.removeAll()
            for aggregate in aggregates {
                self.aggregatesByKey[aggregate.id] = aggregate
            }
            self.isLoaded = true
        }

        // Сохранить в CoreData асинхронно (БЕЗ ожидания - fire and forget)
        repository.saveAggregates(aggregates)
    }

    /// Очистить кеш
    func clear() {
        aggregatesByKey.removeAll()
        isLoaded = false
    }
}

// MARK: - Supporting Types

enum AggregateOperation {
    case add
    case delete
    case update(oldTransaction: Transaction)
}
