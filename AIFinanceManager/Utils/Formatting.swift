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
        "GBP": "£",
        "CNY": "¥",
        "JPY": "¥"
    ]
    
    /// Получает символ валюты по коду
    /// - Parameter currency: Код валюты (например, "USD", "KZT")
    /// - Returns: Символ валюты (например, "$", "₸") или код валюты, если символ не найден
    static func currencySymbol(for currency: String) -> String {
        return currencySymbols[currency.uppercased()] ?? currency
    }
    
    /// Форматирует сумму с символом валюты
    /// - Parameters:
    ///   - amount: Сумма
    ///   - currency: Код валюты
    /// - Returns: Отформатированная строка с символом валюты (например, "1,234.56 $")
    static func formatCurrency(_ amount: Double, currency: String) -> String {
        let symbol = currencySymbol(for: currency)
        
        // Форматируем число с разделителями тысяч
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.groupingSeparator = " "
        numberFormatter.decimalSeparator = "."
        
        guard let formattedAmount = numberFormatter.string(from: NSNumber(value: amount)) else {
            return String(format: "%.2f %@", amount, symbol)
        }
        
        // Возвращаем в формате: сумма + символ (например, "1 234.56 $" или "1,234.56 ₸")
        return "\(formattedAmount) \(symbol)"
    }
}
