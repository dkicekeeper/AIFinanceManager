//
//  Formatting.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct Formatting {
    static let currencySymbols: [String: String] = [
        "KZT": "₸",
        "USD": "$",
        "EUR": "€",
        "RUB": "₽",
        "GBP": "£"
    ]

    // Кешированный форматтер для оптимизации производительности
    private static let cachedCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()

    static func formatCurrency(_ amount: Double, currency: String) -> String {
        // Используем кешированный форматтер
        cachedCurrencyFormatter.currencyCode = currency

        if let formatted = cachedCurrencyFormatter.string(from: NSNumber(value: amount)) {
            return formatted
        }

        // Fallback
        let symbol = currencySymbols[currency.uppercased()] ?? currency
        return String(format: "%.2f %@", amount, symbol)
    }
}
