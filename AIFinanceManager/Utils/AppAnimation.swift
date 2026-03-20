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

    /// Snappy content spring — for content transitions (amount inputs, list changes, toggles).
    /// response 0.3 + damping 0.7 = quick settle with minimal overshoot.
    static let contentSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Gentle spring — for smooth value animations (amount display, error messages, state changes).
    /// response 0.4 + damping 0.8 = soft deceleration, no visible overshoot.
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Hero spring — for hero icon entrance animations (slower, dramatic settle).
    /// response 0.6 + damping 0.7 = visible overshoot with smooth settle.
    static let heroSpring = Animation.spring(response: 0.6, dampingFraction: 0.7)

    /// Progress bar spring — for animated bar width changes.
    /// response 0.55 + damping 0.72 = smooth bar expansion with slight bounce.
    static let progressBarSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)

    /// Facepile entrance spring — for staggered icon pop-in animations.
    /// response 0.4 + damping 0.7 = visible pop with smooth settle.
    static let facepileSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Starting scale for facepile icon entrance (grows from this to 1.0).
    static let facepileHiddenScale: CGFloat = 0.5

    /// Delay increment per facepile icon (each icon delays by `index * facepileStagger`).
    static let facepileStagger: Double = 0.06

    /// Content reveal animation — for staggered section fade-in during initialization.
    static let contentRevealAnimation = Animation.easeOut(duration: 0.35)

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

    // MARK: - Chart Animations

    /// Spring response for chart appearance (marks entering the viewport).
    static let chartAppearResponse: Double = 0.55

    /// Damping fraction for chart appearance spring.
    static let chartAppearDamping: Double = 0.82

    /// Spring response for chart data update (marks repositioning when data changes).
    static let chartUpdateResponse: Double = 0.5

    /// Damping fraction for chart data update spring.
    static let chartUpdateDamping: Double = 0.85

    /// Delay before chart appearance animation starts (lets layout settle).
    static let chartAppearDelay: Double = 0.05

    /// Starting scale for chart appearance (grows from this to 1.0, anchored at bottom).
    static let chartHiddenScale: CGFloat = 0.94

    /// Reduce-Motion-aware spring for chart appearance.
    static var chartAppearAnimation: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: chartAppearResponse, dampingFraction: chartAppearDamping)
    }

    /// Reduce-Motion-aware spring for chart data updates.
    static var chartUpdateAnimation: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: chartUpdateResponse, dampingFraction: chartUpdateDamping)
    }

    // MARK: - Reduce Motion Aware Animations

    /// `true` когда пользователь включил "Reduce Motion" в Настройках → Универсальный доступ.
    /// Используй для условного отключения декоративных анимаций (shimmer, bounce и т.д.).
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// `Animation` для быстрых переходов с учётом Reduce Motion.
    /// Замена для `.easeInOut(duration: AppAnimation.fast)` в местах, где анимация декоративная.
    static var fastAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: fast)
    }

    /// `Animation` для стандартных переходов с учётом Reduce Motion.
    /// Замена для `.easeInOut(duration: AppAnimation.standard)`.
    static var standardAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: standard)
    }

    /// `Animation` для медленных переходов (модальные экраны) с учётом Reduce Motion.
    static var slowAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: slow)
    }

    /// Spring-анимация с учётом Reduce Motion.
    /// Замена для `AppAnimation.spring` в декоративных bounce-эффектах.
    static var adaptiveSpring: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : spring
    }

}

// MARK: - Interactive Button Style

/// Интерактивный стиль кнопки с эффектом увеличения и bounce (iOS 16+ style)
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0.0)
            .animation(AppAnimation.adaptiveSpring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BounceButtonStyle {
    /// Применяет iOS 16+ стиль с эффектом увеличения и bounce при нажатии
    static var bounce: BounceButtonStyle {
        BounceButtonStyle()
    }
}
