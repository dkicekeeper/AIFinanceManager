//
//  AppButton.swift
//  Tenra
//
//  Consistent button styles — Liquid Glass (iOS 26+).
//

import SwiftUI

// MARK: - Convenience Extensions

extension View {
    /// Primary CTA — `.glassProminent` + accent tint + capsule.
    /// Используй для: Save, Add, Confirm, primary actions.
    ///
    /// Sizing follows the button's label — для full-width CTA добавь
    /// `.frame(maxWidth: .infinity)` к содержимому Button.
    ///
    /// `disabled: true` блокирует тапы (`.disabled` modifier) — glass-стиль сам
    /// затемнит кнопку. Дополняет SwiftUI `.disabled()` modifier.
    func primaryButton(disabled: Bool = false) -> some View {
        self
            .buttonStyle(.glassProminent)
            .tint(AppColors.accent)
            .controlSize(.large)
            .disabled(disabled)
    }

    /// Secondary action — `.glass`.
    /// Используй для: Cancel, Back, secondary actions.
    func secondaryButton() -> some View {
        self
            .buttonStyle(.glass)
            .controlSize(.large)
    }
}
