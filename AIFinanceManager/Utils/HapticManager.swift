//
//  HapticManager.swift
//  AIFinanceManager
//
//  Управление тактильной обратной связью (haptic feedback)
//

import UIKit
import SwiftUI

/// Менеджер для консистентного haptic feedback по всему приложению
enum HapticManager {

    // MARK: - Notification Feedback

    /// Успешное действие (сохранение, добавление)
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Предупреждение (удаление, опасное действие)
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    /// Ошибка
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    // MARK: - Impact Feedback

    /// Лёгкое нажатие (выбор элемента, tap)
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Среднее нажатие (кнопки)
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Сильное нажатие (важные действия)
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    // MARK: - Selection Feedback

    /// Изменение выбора (пикеры, сегменты)
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - View Extension для удобного использования

extension View {
    /// Добавляет haptic feedback при tap gesture
    func hapticFeedback(_ style: HapticFeedbackStyle = .light) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                switch style {
                case .light:
                    HapticManager.light()
                case .medium:
                    HapticManager.medium()
                case .heavy:
                    HapticManager.heavy()
                case .selection:
                    HapticManager.selection()
                case .success:
                    HapticManager.success()
                case .warning:
                    HapticManager.warning()
                case .error:
                    HapticManager.error()
                }
            }
        )
    }
}

enum HapticFeedbackStyle {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error
}
