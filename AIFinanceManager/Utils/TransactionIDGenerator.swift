//
//  TransactionIDGenerator.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct TransactionIDGenerator {
    static func generateID(for transaction: Transaction) -> String {
        let normalizedDate = transaction.date.trimmingCharacters(in: .whitespaces)
        let normalizedDescription = normalizeWhitespace(transaction.description)
        let normalizedType = normalizeWhitespace(transaction.type.rawValue)
        let normalizedCurrency = transaction.currency.trimmingCharacters(in: .whitespaces).uppercased()
        let normalizedAmount = String(format: "%.2f", transaction.amount)
        
        let key = "\(normalizedDate)|\(normalizedDescription)|\(normalizedAmount)|\(normalizedType)|\(normalizedCurrency)"
        
        return hashHex(for: key)
    }
    
    static func generateID(date: String, description: String, amount: Double, type: TransactionType, currency: String) -> String {
        let normalizedDate = date.trimmingCharacters(in: .whitespaces)
        let normalizedDescription = normalizeWhitespace(description)
        let normalizedType = normalizeWhitespace(type.rawValue)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespaces).uppercased()
        let normalizedAmount = String(format: "%.2f", amount)
        
        let key = "\(normalizedDate)|\(normalizedDescription)|\(normalizedAmount)|\(normalizedType)|\(normalizedCurrency)"
        
        return hashHex(for: key)
    }
    
    private static func normalizeWhitespace(_ value: String) -> String {
        return value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
    
    private static func hashHex(for value: String) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        let raw = hasher.finalize()
        let unsigned = UInt64(bitPattern: Int64(raw))
        return String(format: "%016llx", unsigned)
    }
}
