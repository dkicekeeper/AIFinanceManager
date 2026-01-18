//
//  MLDataExporter.swift
//  AIFinanceManager
//
//  Created on 2026-01-18
//

import Foundation

/// Утилита для экспорта данных для обучения ML моделей
class MLDataExporter {

    // MARK: - Category Training Data

    /// Экспортирует данные транзакций в CSV для обучения модели категорий
    /// - Parameter transactions: Массив транзакций
    /// - Returns: CSV строка
    static func exportCategoryTrainingData(from transactions: [Transaction]) -> String {
        var csv = "description,category,amount,type\n"

        for transaction in transactions {
            // Экранируем спецсимволы
            let description = escapeCSV(transaction.description)
            let categoryEscaped = escapeCSV(transaction.category)
            let amount = transaction.amount
            let type = transaction.type == .expense ? "expense" : "income"

            csv += "\(description),\(categoryEscaped),\(amount),\(type)\n"
        }

        return csv
    }

    /// Экспортирует данные для обучения модели предсказания счетов
    /// - Parameter transactions: Массив транзакций
    /// - Returns: CSV строка
    static func exportAccountTrainingData(from transactions: [Transaction]) -> String {
        var csv = "description,account_id,category,amount\n"

        for transaction in transactions {
            let description = escapeCSV(transaction.description)
            let accountId = escapeCSV(transaction.accountId ?? "")
            let category = escapeCSV(transaction.category)
            let amount = transaction.amount

            csv += "\(description),\(accountId),\(category),\(amount)\n"
        }

        return csv
    }

    // MARK: - Statistics

    /// Собирает статистику для анализа качества данных
    /// - Parameter transactions: Массив транзакций
    /// - Returns: Словарь статистики
    static func collectStatistics(from transactions: [Transaction]) -> [String: Any] {
        let totalCount = transactions.count

        // Группировка по категориям
        let categoryGroups = Dictionary(grouping: transactions) { $0.category }
        let categoryStats = categoryGroups.mapValues { $0.count }

        // Группировка по счетам
        let accountGroups = Dictionary(grouping: transactions) { $0.accountId ?? "unknown" }
        let accountStats = accountGroups.mapValues { $0.count }

        // Группировка по типу
        let expenseCount = transactions.filter { $0.type == .expense }.count
        let incomeCount = transactions.filter { $0.type == .income }.count

        // Средняя длина описания
        let avgDescriptionLength = transactions
            .map { $0.description.count }
            .reduce(0, +) / max(totalCount, 1)

        return [
            "total_transactions": totalCount,
            "category_distribution": categoryStats,
            "account_distribution": accountStats,
            "expense_count": expenseCount,
            "income_count": incomeCount,
            "expense_ratio": Double(expenseCount) / Double(max(totalCount, 1)),
            "avg_description_length": avgDescriptionLength,
            "categories_count": categoryGroups.count,
            "accounts_count": accountGroups.count
        ]
    }

    /// Проверяет, достаточно ли данных для обучения
    /// - Parameter transactions: Массив транзакций
    /// - Returns: (достаточно ли данных, сообщение)
    static func validateTrainingData(transactions: [Transaction]) -> (isValid: Bool, message: String) {
        let minTransactions = 50  // Минимум для обучения
        let minCategoriesPerClass = 5  // Минимум примеров на категорию

        guard transactions.count >= minTransactions else {
            return (false, "Недостаточно транзакций. Нужно минимум \(minTransactions), есть \(transactions.count)")
        }

        let categoryGroups = Dictionary(grouping: transactions) { $0.category }

        // Проверяем, что у каждой категории достаточно примеров
        let thinCategories = categoryGroups.filter { $0.value.count < minCategoriesPerClass }

        if !thinCategories.isEmpty {
            let categoriesList = thinCategories.keys.joined(separator: ", ")
            return (false, "Недостаточно примеров для категорий: \(categoriesList). Нужно минимум \(minCategoriesPerClass) на категорию")
        }

        return (true, "Данных достаточно для обучения")
    }

    // MARK: - File Export

    /// Сохраняет CSV в файл
    /// - Parameters:
    ///   - csv: CSV строка
    ///   - filename: Имя файла
    /// - Returns: URL файла или nil
    static func saveToFile(csv: String, filename: String) -> URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let fileURL = documentsURL.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Ошибка сохранения CSV: \(error)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private static func escapeCSV(_ text: String) -> String {
        // Если текст содержит запятую, кавычку или перенос строки - оборачиваем в кавычки
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }
}

// MARK: - Debug Helper

#if DEBUG
extension MLDataExporter {
    /// Генерирует отчет о готовности данных для ML
    static func generateDataReadinessReport(from transactions: [Transaction]) -> String {
        let stats = collectStatistics(from: transactions)
        let validation = validateTrainingData(transactions: transactions)

        var report = """
        📊 ML Data Readiness Report
        ===========================

        Total Transactions: \(stats["total_transactions"] ?? 0)
        Categories: \(stats["categories_count"] ?? 0)
        Accounts: \(stats["accounts_count"] ?? 0)

        Type Distribution:
        - Expenses: \(stats["expense_count"] ?? 0) (\(String(format: "%.1f%%", (stats["expense_ratio"] as? Double ?? 0) * 100)))
        - Income: \(stats["income_count"] ?? 0)

        Average Description Length: \(stats["avg_description_length"] ?? 0) characters

        Category Distribution:
        """

        if let categoryDist = stats["category_distribution"] as? [String: Int] {
            for (category, count) in categoryDist.sorted(by: { $0.value > $1.value }) {
                report += "\n  - \(category): \(count) transactions"
            }
        }

        report += "\n\nValidation: \(validation.isValid ? "✅ PASSED" : "❌ FAILED")"
        report += "\nMessage: \(validation.message)"

        if validation.isValid {
            report += "\n\n✅ Ready to train ML model!"
            report += "\n\nNext steps:"
            report += "\n1. Export CSV: MLDataExporter.saveToFile()"
            report += "\n2. Open Create ML on Mac"
            report += "\n3. Train Text Classifier model"
            report += "\n4. Add .mlmodel to project"
        }

        return report
    }
}
#endif
