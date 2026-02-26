//
//  AppShadow.swift
//  AIFinanceManager
//
//  Shadow tokens for consistent depth styling.
//

import SwiftUI

// MARK: - Shadow System

/// Консистентная система теней
enum AppShadow {
    /// Нет тени
    static let none = Shadow(color: .clear, radius: 0, x: 0, y: 0)

    /// Малая тень (hover states, небольшая глубина)
    static let sm = Shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)

    /// Средняя тень (cards, buttons)
    static let md = Shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

    /// Большая тень (floating buttons, modals)
    static let lg = Shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
}

// MARK: - Shadow Value Type

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}
