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
    
    static func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "ru_RU")
        
        if let formatted = formatter.string(from: NSNumber(value: amount)) {
            return formatted
        }
        
        // Fallback
        let symbol = currencySymbols[currency.uppercased()] ?? currency
        return String(format: "%.2f %@", amount, symbol)
    }
    
    static func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let transactionYear = calendar.component(.year, from: date)
        
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "ru_RU")
        
        if transactionYear == currentYear {
            displayFormatter.dateFormat = "d MMMM"
        } else {
            displayFormatter.dateFormat = "d MMMM yyyy"
        }
        
        return displayFormatter.string(from: date)
    }
}
