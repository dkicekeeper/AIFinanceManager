//
//  AppColors.swift
//  AIFinanceManager
//
//  Semantic color tokens + category palette. Single source of truth for all colors.
//

import SwiftUI

// MARK: - Semantic Colors

/// Семантические цвета приложения (дополняют существующую систему)
enum AppColors {
    // MARK: Backgrounds

    /// Фон primary экрана
    static let backgroundPrimary = Color(.systemBackground)

    /// Фон surface (карточки, elevated elements)
    static let surface = Color(.secondarySystemBackground)

    /// Фон основных карточек (alias для surface)
    static let cardBackground = surface

    /// Фон вторичных элементов (chips, secondary buttons)
    static let secondaryBackground = Color(.systemGray5)

    /// Фон экрана (alias для backgroundPrimary)
    static let screenBackground = backgroundPrimary

    // MARK: Text Colors

    /// Primary text (используй системный .primary для auto light/dark)
    static let textPrimary = Color.primary

    /// Secondary text (используй системный .secondary для auto light/dark)
    static let textSecondary = Color.secondary

    /// Tertiary text (используй системный .gray для мета-информации)
    static let textTertiary = Color.gray

    // MARK: Interactive Colors

    /// Accent color (для выделений, selections)
    static let accent = Color.blue

    /// Destructive actions
    static let destructive = Color.red

    /// Success/positive
    static let success = Color.green

    /// Warning
    static let warning = Color.orange

    // MARK: Dividers & Borders

    /// Divider color
    static let divider = Color(.separator)

    /// Border color
    static let border = Color(.systemGray4)

    // MARK: Transaction Type Colors (semantic)

    /// Income transactions
    static let income = Color.green

    /// Expense transactions
    static let expense = Color.primary

    /// Transfer / internal transactions (distinct cyan-teal, not accent blue)
    static let transfer = Color(red: 0.0, green: 0.75, blue: 0.85)

    /// Planned / future / scheduled transactions
    static let planned = Color.blue

    // MARK: Status Colors (explicit aliases)

    /// Active status (alias for success)
    static let statusActive = success

    /// Paused status (alias for warning)
    static let statusPaused = warning

    /// Archived / inactive status
    static let statusArchived = Color(.systemGray)
}

// MARK: - Category Color Palette

/// Цвета для категорий транзакций — hash-based assignment из палитры
struct CategoryColors {
    static let palette: [Color] = [
        .blue, .cyan, .pink, .orange, .yellow,
        .green, .teal, .indigo, .purple, .mint,
        .red, .purple, .green, .orange
    ]

    /// Возвращает цвет из палитры по хэшу имени категории
    static func color(for category: String, opacity: Double = 1.0) -> Color {
        let index = abs(category.hashValue) % palette.count
        return palette[index].opacity(opacity)
    }

    /// Возвращает цвет по hex-палитре с учётом пользовательских категорий
    static func hexColor(for category: String, opacity: Double = 1.0, customCategories: [CustomCategory] = []) -> Color {
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() }) {
            return custom.color.opacity(opacity)
        }

        let colors: [String] = [
            "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
            "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
            "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
        ]

        let hex = colors[abs(category.hashValue) % colors.count]
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        return Color(
            red:   Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8)  / 255.0,
            blue:  Double( rgb & 0x0000FF)         / 255.0,
            opacity: opacity
        )
    }
}
