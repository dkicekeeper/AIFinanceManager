//
//  PerformanceLogger.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Расширенное логирование производительности для анализа медленного открытия истории
//

import Foundation

/// Расширенный логгер производительности с детальной аналитикой
@MainActor
class PerformanceLogger {

    // MARK: - Singleton

    static let shared = PerformanceLogger()

    // MARK: - Properties

    private var measurements: [String: MeasurementData] = [:]
    private var isEnabled = true

    // MARK: - Measurement Data

    struct MeasurementData {
        let operationName: String
        let startTime: CFAbsoluteTime
        var endTime: CFAbsoluteTime?
        var metadata: [String: Any] = [:]

        var duration: TimeInterval? {
            guard let endTime = endTime else { return nil }
            return endTime - startTime
        }

        var durationMs: Double? {
            guard let duration = duration else { return nil }
            return duration * 1000
        }
    }

    // MARK: - Configuration

    func enable() {
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }

    // MARK: - Measurement API

    /// Начать измерение производительности операции
    /// - Parameters:
    ///   - name: Уникальное имя операции
    ///   - metadata: Дополнительные метаданные (например, количество элементов)
    func start(_ name: String, metadata: [String: Any] = [:]) {
        guard isEnabled else { return }

        let measurement = MeasurementData(
            operationName: name,
            startTime: CFAbsoluteTimeGetCurrent(),
            metadata: metadata
        )
        measurements[name] = measurement

    }

    /// Завершить измерение производительности операции
    /// - Parameters:
    ///   - name: Уникальное имя операции
    ///   - additionalMetadata: Дополнительные метаданные для завершения
    func end(_ name: String, additionalMetadata: [String: Any] = [:]) {
        guard isEnabled else { return }

        guard var measurement = measurements[name] else {
            return
        }

        measurement.endTime = CFAbsoluteTimeGetCurrent()
        measurement.metadata.merge(additionalMetadata) { _, new in new }
        measurements[name] = measurement

    }

    /// Измерить производительность блока кода
    /// - Parameters:
    ///   - name: Имя операции
    ///   - metadata: Метаданные
    ///   - block: Блок кода для измерения
    func measure<T>(_ name: String, metadata: [String: Any] = [:], block: () throws -> T) rethrows -> T {
        start(name, metadata: metadata)
        defer { end(name) }
        return try block()
    }

    /// Измерить производительность асинхронного блока кода
    /// - Parameters:
    ///   - name: Имя операции
    ///   - metadata: Метаданные
    ///   - block: Асинхронный блок кода
    func measureAsync<T>(_ name: String, metadata: [String: Any] = [:], block: () async throws -> T) async rethrows -> T {
        start(name, metadata: metadata)
        defer { end(name) }
        return try await block()
    }

    // MARK: - Reporting

    /// Получить отчет о всех измерениях
    func getReport() -> String {
        var report = "\n" + String(repeating: "=", count: 80) + "\n"
        report += "📊 PERFORMANCE REPORT\n"
        report += String(repeating: "=", count: 80) + "\n\n"

        let sortedMeasurements = measurements.values.sorted { m1, m2 in
            (m1.durationMs ?? 0) > (m2.durationMs ?? 0)
        }

        var totalTime: Double = 0

        for measurement in sortedMeasurements {
            guard let durationMs = measurement.durationMs else { continue }
            totalTime += durationMs

            let severity = getSeverity(durationMs: durationMs)
            let metadataString = formatMetadata(measurement.metadata)

            report += "\(severity) \(measurement.operationName): \(String(format: "%.2f", durationMs))ms\(metadataString)\n"
        }

        report += "\n" + String(repeating: "-", count: 80) + "\n"
        report += "TOTAL TIME: \(String(format: "%.2f", totalTime))ms\n"
        report += String(repeating: "=", count: 80) + "\n"

        return report
    }

    /// Вывести отчет в консоль
    func printReport() {
    }

    /// Очистить все измерения
    func reset() {
        measurements.removeAll()
    }

    // MARK: - Analysis Helpers

    /// Получить метрику по имени
    func getMeasurement(_ name: String) -> MeasurementData? {
        return measurements[name]
    }

    /// Получить все медленные операции (> threshold мс)
    func getSlowOperations(threshold: Double = 100) -> [MeasurementData] {
        return measurements.values.filter { measurement in
            guard let durationMs = measurement.durationMs else { return false }
            return durationMs > threshold
        }.sorted { m1, m2 in
            (m1.durationMs ?? 0) > (m2.durationMs ?? 0)
        }
    }

    // MARK: - Private Helpers

    private func getSeverity(durationMs: Double) -> String {
        switch durationMs {
        case 0..<10:
            return "✅" // Отлично
        case 10..<50:
            return "🟢" // Хорошо
        case 50..<100:
            return "🟡" // Приемлемо
        case 100..<300:
            return "🟠" // Медленно
        default:
            return "🔴" // Критично медленно
        }
    }

    private func formatMetadata(_ metadata: [String: Any]) -> String {
        guard !metadata.isEmpty else { return "" }

        let items = metadata.map { key, value in
            "\(key): \(value)"
        }.joined(separator: ", ")

        return " [\(items)]"
    }
}

// MARK: - Convenience Extensions

extension PerformanceLogger {

    /// Логирование для HistoryView
    struct HistoryMetrics {
        static func logOnAppear(transactionCount: Int) {
            shared.start("HistoryView.onAppear", metadata: ["totalTransactions": transactionCount])
        }

        static func logUpdateTransactions(transactionCount: Int, hasFilters: Bool) {
            shared.start("HistoryView.updateTransactions", metadata: [
                "transactionCount": transactionCount,
                "hasFilters": hasFilters
            ])
        }

        static func logFilterTransactions(inputCount: Int, outputCount: Int, accountFilter: Bool, searchText: String) {
            shared.start("TransactionFilter.filterForHistory", metadata: [
                "inputCount": inputCount,
                "outputCount": outputCount,
                "hasAccountFilter": accountFilter,
                "searchTextLength": searchText.count
            ])
        }

        static func logGroupTransactions(transactionCount: Int, sectionCount: Int) {
            shared.start("TransactionGrouping.groupByDate", metadata: [
                "transactionCount": transactionCount,
                "sectionCount": sectionCount
            ])
        }

        static func logPagination(totalSections: Int, visibleSections: Int) {
            shared.start("Pagination.initialize", metadata: [
                "totalSections": totalSections,
                "visibleSections": visibleSections
            ])
        }

        static func logTransactionCardRender(index: Int, transactionId: String) {
            shared.start("TransactionCard.render.\(transactionId)", metadata: [
                "index": index
            ])
        }
    }

    /// Логирование для фильтрации по категориям
    struct CategoryFilterMetrics {
        static func logFilterStart(categoryCount: Int) {
            shared.start("CategoryFilter.apply", metadata: [
                "categoryCount": categoryCount
            ])
        }

        static func logAccountFilterStart(accountCount: Int) {
            shared.start("AccountFilter.apply", metadata: [
                "accountCount": accountCount
            ])
        }
    }

    /// Логирование для операций с подкатегориями
    struct SubcategoryMetrics {
        static func logLookup(transactionId: String, subcategoryCount: Int) {
            shared.start("Subcategory.lookup.\(transactionId)", metadata: [
                "subcategoryCount": subcategoryCount
            ])
        }
    }

    // MARK: - Insights Metrics (Phase 17)

    /// Структурированное логирование для InsightsService и InsightsViewModel.
    /// Каждый метод соответствует одному логическому этапу генерации инсайтов.
    struct InsightsMetrics {

        // MARK: ViewModel

        static func logLoadStart(transactionCount: Int, timeFilter: String, currency: String) {
            shared.start("Insights.loadInsights", metadata: [
                "transactions": transactionCount,
                "filter": timeFilter,
                "currency": currency
            ])
        }

        static func logLoadEnd(insightCount: Int, monthlyPointCount: Int) {
            shared.end("Insights.loadInsights", additionalMetadata: [
                "insightsGenerated": insightCount,
                "monthlyPoints": monthlyPointCount
            ])
        }

        // MARK: Service — top level

        static func logGenerateStart(filteredCount: Int, cacheHit: Bool) {
            shared.start("Insights.generateAll", metadata: [
                "filteredTransactions": filteredCount,
                "cacheHit": cacheHit
            ])
        }

        static func logGenerateEnd(total: Int) {
            shared.end("Insights.generateAll", additionalMetadata: ["totalInsights": total])
        }

        // MARK: Spending

        static func logSpendingStart(expenseCount: Int, categoryCount: Int) {
            shared.start("Insights.spending", metadata: [
                "expenses": expenseCount,
                "categories": categoryCount
            ])
        }

        static func logSpendingEnd(insightCount: Int, topCategory: String, topAmount: Double) {
            shared.end("Insights.spending", additionalMetadata: [
                "insights": insightCount,
                "topCategory": topCategory,
                "topAmount": String(format: "%.0f", topAmount)
            ])
        }

        // MARK: Income

        static func logIncomeStart(incomeCount: Int) {
            shared.start("Insights.income", metadata: ["incomeTransactions": incomeCount])
        }

        static func logIncomeEnd(insightCount: Int, thisMonth: Double, prevMonth: Double) {
            let change = prevMonth > 0 ? ((thisMonth - prevMonth) / prevMonth) * 100 : 0
            shared.end("Insights.income", additionalMetadata: [
                "insights": insightCount,
                "thisMonth": String(format: "%.0f", thisMonth),
                "prevMonth": String(format: "%.0f", prevMonth),
                "changePercent": String(format: "%+.1f%%", change)
            ])
        }

        // MARK: Budget

        static func logBudgetStart(categoriesWithBudget: Int) {
            shared.start("Insights.budget", metadata: ["budgetCategories": categoriesWithBudget])
        }

        static func logBudgetEnd(insightCount: Int, overBudget: Int, atRisk: Int, underBudget: Int) {
            shared.end("Insights.budget", additionalMetadata: [
                "insights": insightCount,
                "overBudget": overBudget,
                "atRisk": atRisk,
                "underBudget": underBudget
            ])
        }

        // MARK: Recurring

        static func logRecurringStart(activeSeries: Int) {
            shared.start("Insights.recurring", metadata: ["activeSeries": activeSeries])
        }

        static func logRecurringEnd(totalMonthly: Double, currency: String) {
            shared.end("Insights.recurring", additionalMetadata: [
                "totalMonthly": String(format: "%.0f %@", totalMonthly, currency)
            ])
        }

        // MARK: CashFlow

        static func logCashFlowStart(months: Int) {
            shared.start("Insights.cashFlow", metadata: ["months": months])
        }

        static func logCashFlowEnd(insightCount: Int, latestNetFlow: Double, projectedBalance: Double) {
            shared.end("Insights.cashFlow", additionalMetadata: [
                "insights": insightCount,
                "latestNetFlow": String(format: "%.0f", latestNetFlow),
                "projectedBalance": String(format: "%.0f", projectedBalance)
            ])
        }

        // MARK: Monthly Data Points

        static func logMonthlyPointStart(months: Int, transactionCount: Int) {
            shared.start("Insights.monthlyPoints", metadata: [
                "months": months,
                "transactions": transactionCount
            ])
        }

        static func logMonthlyPointEnd(pointCount: Int) {
            shared.end("Insights.monthlyPoints", additionalMetadata: ["pointsComputed": pointCount])
        }
    }
}
