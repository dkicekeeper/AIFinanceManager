//
//  AppModifiers.swift
//  AIFinanceManager
//
//  SwiftUI view modifiers for consistent styling across the app.
//

import SwiftUI

// MARK: - Card & Row Styles

extension View {
    /// Interactive filter chip — uses Liquid Glass on iOS 26+; falls back to tinted `secondaryBackground`.
    ///
    /// The `isSelected` state adds an `accent` tint on both platforms.
    ///
    /// **Use when:** the chip triggers filtering, navigation, or any tap action
    /// (filter buttons, action menu triggers, segmented-style selectors in toolbars).
    @ViewBuilder
    func filterChipStyle(isSelected: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self
                .font(AppTypography.bodySmall.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: AppRadius.xl))
                .glassEffect(
                    isSelected
                    ? .regular.tint(AppColors.accent.opacity(0.2)).interactive()
                    : .regular.interactive()
                )
        } else {
            self
                .font(AppTypography.bodySmall.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isSelected
                    ? AppColors.accent.opacity(0.2)
                    : AppColors.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: AppRadius.xl)
                )
        }
    }

    /// Применяет glass effect с стандартным cornerRadius для карточек (iOS 26+)
    /// Padding НЕ добавляется — ответственность за отступы лежит на содержимом
    /// (строки используют собственный padding; произвольный контент добавляет .padding перед вызовом)
    @ViewBuilder
    func cardStyle(radius: CGFloat = AppRadius.xl) -> some View {
        if #available(iOS 26, *) {
            self
                .contentShape(Rectangle())
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }
}

// MARK: - Layout Helpers

extension View {
    /// Стандартный horizontal padding для экранов
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.pageHorizontal)
    }

    /// Визуально приглушает view для будущих / запланированных транзакций.
    /// Применяй вместо inline `opacity(0.5)` чтобы значение было единым по всему проекту.
    func futureTransactionStyle(isFuture: Bool) -> some View {
        self.opacity(isFuture ? 0.55 : 1.0)
    }

    /// Card padding (внутренний padding карточек)
    func cardContentPadding() -> some View {
        self.padding(AppSpacing.cardPadding)
    }
}

// MARK: - Chart Appear Modifier

/// Animates a chart's entrance: fades in + scales up from the bottom edge.
///
/// Apply to any chart container view. Triggers once on first appearance.
/// Respects the user's Reduce Motion accessibility setting.
///
/// ```swift
/// SpendingTrendChart(dataPoints: points, currency: "KZT")
///     .chartAppear()
/// ```
struct ChartAppearModifier: ViewModifier {
    @State private var appeared = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : AppAnimation.chartHiddenScale, anchor: .bottom)
            .onAppear {
                withAnimation(
                    AppAnimation.chartAppearAnimation
                        .delay(AppAnimation.chartAppearDelay + delay)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// Animates chart entrance with opacity + scale spring from the bottom.
    /// - Parameter delay: Extra delay before animation starts (use to stagger multiple charts).
    func chartAppear(delay: Double = 0) -> some View {
        modifier(ChartAppearModifier(delay: delay))
    }
}
