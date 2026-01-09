//
//  CSVExporter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

class CSVExporter {
    static func exportTransactions(_ transactions: [Transaction], accounts: [Account]) -> String {
        var csv = "date,type,amount,currency,account,category,subcategories,note\n"
        
        for transaction in transactions {
            let date = transaction.date
            let type = transaction.type == .expense ? "expense" : transaction.type == .income ? "income" : "internal"
            let amount = String(format: "%.2f", transaction.amount)
            let currency = escapeCSVField(transaction.currency)
            let accountName = escapeCSVField(accounts.first(where: { $0.id == transaction.accountId })?.name ?? "")
            let category = escapeCSVField(transaction.category)
            let subcategories = escapeCSVField(transaction.subcategory ?? "")
            let note = escapeCSVField(transaction.description)
            
            csv += "\(date),\(type),\(amount),\(currency),\(accountName),\(category),\(subcategories),\(note)\n"
        }
        
        return csv
    }
    
    private static func escapeCSVField(_ field: String) -> String {
        // Если поле содержит запятую, кавычку или перенос строки, оборачиваем в кавычки
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            // Экранируем кавычки удвоением
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

extension DateFormatter {
    static let exportFileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
