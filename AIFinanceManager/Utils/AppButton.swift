//
//  AppButton.swift
//  AIFinanceManager
//
//  Консистентные стили кнопок
//

import SwiftUI

// MARK: - Button Styles

/// Primary Button - основное действие (CTA)
/// Используй для: Save, Add, Confirm, Primary actions
struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.bodyLarge)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(isDisabled ? Color.gray : Color.blue)
            .clipShape(.rect(cornerRadius: AppRadius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: configuration.isPressed)
    }
}

/// Secondary Button - второстепенное действие
/// Используй для: Cancel, Back, Secondary actions
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.secondaryBackground)
            .clipShape(.rect(cornerRadius: AppRadius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: configuration.isPressed)
    }
}

/// Tertiary Button - неакцентированное действие (текстовая кнопка)
/// Используй для: Links, "See all", optional actions
struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundStyle(.blue)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: configuration.isPressed)
    }
}

/// Destructive Button - опасное действие
/// Используй для: Delete, Reset, Remove
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.bodyLarge)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(Color.red)
            .clipShape(.rect(cornerRadius: AppRadius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: configuration.isPressed)
    }
}

// MARK: - Date Buttons Style (special case)

/// Стиль для кнопок выбора даты (Вчера/Сегодня/Календарь)
/// Это специализированный стиль для DateButtonsView
struct DateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.secondaryBackground)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: configuration.isPressed)
    }
}

// MARK: - Convenience Extensions

extension View {
    /// Применяет primary button style
    func primaryButton(disabled: Bool = false) -> some View {
        self.buttonStyle(PrimaryButtonStyle(isDisabled: disabled))
    }

    /// Применяет secondary button style
    func secondaryButton() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }

    /// Применяет tertiary button style
    func tertiaryButton() -> some View {
        self.buttonStyle(TertiaryButtonStyle())
    }

    /// Применяет destructive button style
    func destructiveButton() -> some View {
        self.buttonStyle(DestructiveButtonStyle())
    }

    /// Применяет date button style
    func dateButton() -> some View {
        self.buttonStyle(DateButtonStyle())
    }
}
