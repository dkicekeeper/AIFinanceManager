//
//  AmountDisplayConfiguration.swift
//  AIFinanceManager
//
//  Created on 2026-02-11
//  Centralized configuration for amount display formatting
//

import Foundation

/// Централизованная конфигурация для отображения денежных сумм
struct AmountDisplayConfiguration {
    /// Показывать ли сотые, если они равны нулю
    /// - true: всегда показывать (1000.00)
    /// - false: скрывать если ноль (1000)
    var showDecimalsWhenZero: Bool = false

    /// Прозрачность дробной части (0.0...1.0)
    var decimalOpacity: Double = 0.5

    /// Разделитель тысяч
    var thousandsSeparator: String = " "

    /// Десятичный разделитель
    var decimalSeparator: String = "."

    /// Минимальное количество знаков после запятой
    var minimumFractionDigits: Int = 2

    /// Максимальное количество знаков после запятой
    var maximumFractionDigits: Int = 2

    /// Глобальный экземпляр конфигурации
    static var shared = AmountDisplayConfiguration()

    /// Создает NumberFormatter на основе текущей конфигурации
    func makeNumberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = thousandsSeparator
        formatter.decimalSeparator = decimalSeparator
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.usesGroupingSeparator = true
        return formatter
    }
}
