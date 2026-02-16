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
}
