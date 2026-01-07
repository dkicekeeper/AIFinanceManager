//
//  Colors.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct CategoryColors {
    static let palette: [Color] = [
        .blue, .cyan, .pink, .orange, .yellow,
        .green, .teal, .indigo, .purple, .mint,
        .red, .purple, .green, .orange
    ]
    
    static func color(for category: String, opacity: Double = 1.0) -> Color {
        let hash = category.hashValue
        let index = abs(hash) % palette.count
        return palette[index].opacity(opacity)
    }
    
    static func hexColor(for category: String, opacity: Double = 1.0, customCategories: [CustomCategory] = []) -> Color {
        // Сначала проверяем пользовательские категории
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() }) {
            return custom.color.opacity(opacity)
        }
        
        // Затем дефолтные
        let colors: [String] = [
            "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
            "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
            "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
        ]
        
        let hash = abs(category.hashValue)
        let index = hash % colors.count
        let hex = colors[index]
        
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b, opacity: opacity)
    }
}
