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
    /// Явный disabled параметр — дополняет `.disabled()` SwiftUI modifier.
    /// Предпочтительный способ: используй `.primaryButton(disabled: true)`,
    /// который применяет и этот стиль, и `.disabled()` на View.
    var isDisabled: Bool = false

    /// Читаем disabled state из SwiftUI environment — реагирует на `.disabled()`.
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let effectivelyDisabled = isDisabled || !isEnabled
        configuration.label
            .font(AppTypography.bodyLarge)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.accent)
            .clipShape(.rect(cornerRadius: AppRadius.md))
            .opacity(effectivelyDisabled ? 0.4 : 1.0)
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
            .foregroundStyle(AppColors.accent)
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
            .background(AppColors.destructive)
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
    /// Применяет primary button style.
    /// `disabled: true` визуально скрывает кнопку (opacity 0.4) И блокирует тапы (.disabled modifier).
    func primaryButton(disabled: Bool = false) -> some View {
        self
            .buttonStyle(PrimaryButtonStyle(isDisabled: disabled))
            .disabled(disabled)
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
