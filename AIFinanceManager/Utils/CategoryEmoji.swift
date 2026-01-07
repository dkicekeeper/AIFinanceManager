//
//  CategoryEmoji.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

enum CategoryEmoji {
    static func emoji(for category: String, type: TransactionType, customCategories: [CustomCategory] = []) -> String {
        // Сначала проверяем пользовательские категории
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() && $0.type == type }) {
            return custom.emoji
        }
        
        // Затем дефолтные
        let key = category.lowercased()
        let map: [String: String] = [
            "income": "💵",
            "food": "🍔",
            "transport": "🚕",
            "shopping": "🛍️",
            "entertainment": "🎉",
            "bills": "💡",
            "health": "🏥",
            "education": "🎓",
            "other": "💰",
            "salary": "💼",
            "delivery": "📦",
            "gifts": "🎁",
            "travel": "✈️",
            "groceries": "🛒",
            "coffee": "☕️",
            "subscriptions": "📺"
        ]
        if let value = map[key] { return value }
        return type == .income ? "💵" : "💰"
    }
}
