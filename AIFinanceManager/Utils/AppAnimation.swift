//
//  AppAnimation.swift
//  AIFinanceManager
//
//  Animation tokens and interactive button style.
//

import SwiftUI

// MARK: - Animation Durations

/// Консистентные длительности анимаций
enum AppAnimation {
    // MARK: - Basic Durations

    /// Быстрая анимация (button press, selection)
    static let fast: Double = 0.1

    /// Стандартная анимация (transitions, state changes)
    static let standard: Double = 0.25

    /// Медленная анимация (modals, large transitions)
    static let slow: Double = 0.35

    /// Spring animation для bounce эффекта (iOS 16+ style)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)

    // MARK: - Skeleton Loading

    /// Shimmer sweep duration (left-to-right single pass)
    static let shimmerDuration: Double = 1.4

    /// SkeletonLoadingModifier spring response (skeleton ↔ content transition)
    static let skeletonResponse: Double = 0.4

    /// Scale value for skeleton entrance/exit transition
    static let skeletonScale: CGFloat = 0.97

    /// Opacity of shimmer highlight in dark mode
    static let shimmerOpacityDark: CGFloat = 0.15

    /// Opacity of shimmer highlight in light mode
    static let shimmerOpacityLight: CGFloat = 0.6

    // MARK: - MessageBanner

    /// Banner entrance spring response
    static let bannerEntranceResponse: Double = 0.6

    /// Banner entrance spring damping fraction
    static let bannerEntranceDamping: Double = 0.7

    /// Icon bounce spring response
    static let bannerIconResponse: Double = 0.5

    /// Icon bounce spring damping fraction
    static let bannerIconDamping: Double = 0.6

    /// Icon bounce animation delay (after banner entrance)
    static let bannerIconDelay: Double = 0.1

    /// Banner scale when hidden (entrance starts from this value)
    static let bannerHiddenScale: CGFloat = 0.85

    /// Banner Y-offset when hidden (slides in from above)
    static let bannerHiddenOffset: CGFloat = -20
}

// MARK: - Interactive Button Style

/// Интерактивный стиль кнопки с эффектом увеличения и bounce (iOS 16+ style)
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0.0)
            .animation(AppAnimation.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BounceButtonStyle {
    /// Применяет iOS 16+ стиль с эффектом увеличения и bounce при нажатии
    static var bounce: BounceButtonStyle {
        BounceButtonStyle()
    }
}
