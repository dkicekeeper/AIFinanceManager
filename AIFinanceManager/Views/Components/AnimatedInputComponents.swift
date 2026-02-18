//
//  AnimatedInputComponents.swift
//  AIFinanceManager
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Shared building blocks for animated text/amount input:
//  - AnimatedChar: character data model with animation state tracking
//  - AnimatedDigit: individual character view with spring + wobble animation
//  - AnimatedTitleChar: softer character animation for title text
//  - BlinkingCursor: blinking insertion point indicator
//  - ContainerWidthKey: PreferenceKey for adaptive font sizing
//

import SwiftUI

// MARK: - AnimatedChar

/// Data model for a single animated character
struct AnimatedChar: Identifiable {
    let id: UUID
    let character: Character
    var isNew: Bool
}

// MARK: - AnimatedDigit

/// Renders a single digit/character with spring entrance + wobble effect.
/// Used for numeric amount input.
struct AnimatedDigit: View {
    let character: Character
    let isNew: Bool
    let fontSize: CGFloat
    let color: Color

    @State private var offset: CGFloat = 20
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = 0
    @State private var previousCharacter: Character?

    var body: some View {
        Text(String(character))
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .offset(y: offset)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                if isNew {
                    animateAppearance()
                } else {
                    offset = 0
                    scale = 1.0
                    rotation = 0
                }
                previousCharacter = character
            }
            .onChange(of: isNew) { oldValue, newValue in
                if newValue && !oldValue {
                    animateAppearance()
                }
            }
            .onChange(of: character) { oldValue, newValue in
                if oldValue != newValue {
                    animateAppearance()
                }
                previousCharacter = newValue
            }
    }

    private func animateAppearance() {
        offset = 20
        scale = 0.5
        rotation = 0

        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            offset = 0
            scale = 1.0
        }

        // Wobble sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 0 }
        }
    }
}

// MARK: - AnimatedTitleChar

/// Renders a single text character with spring entrance + wobble effect.
/// Matches AnimatedDigit behaviour — same spring params, same wobble sequence.
struct AnimatedTitleChar: View {
    let character: Character
    let isNew: Bool
    let font: Font
    let color: Color

    @State private var offset: CGFloat = 20
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = 0
    @State private var previousCharacter: Character?

    var body: some View {
        Text(String(character))
            .font(font)
            .foregroundStyle(color)
            .offset(y: offset)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                if isNew {
                    animateAppearance()
                } else {
                    offset = 0
                    scale = 1.0
                    rotation = 0
                }
                previousCharacter = character
            }
            .onChange(of: isNew) { oldValue, newValue in
                if newValue && !oldValue {
                    animateAppearance()
                }
            }
            .onChange(of: character) { oldValue, newValue in
                if oldValue != newValue {
                    animateAppearance()
                }
                previousCharacter = newValue
            }
    }

    private func animateAppearance() {
        offset = 20
        scale = 0.5
        rotation = 0

        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            offset = 0
            scale = 1.0
        }

        // Wobble sequence — идентична AnimatedDigit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) { rotation = 0 }
        }
    }
}

// MARK: - BlinkingCursor

/// Animated blinking cursor shown when input is focused.
struct BlinkingCursor: View {
    var height: CGFloat = AppSize.cursorHeight

    @State private var opacity: Double = 1.0

    var body: some View {
        Rectangle()
            .fill(AppColors.textPrimary)
            .frame(width: AppSize.cursorWidth, height: height)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    opacity = 0.0
                }
            }
            .onDisappear {
                opacity = 1.0
            }
    }
}

// MARK: - ContainerWidthKey

/// PreferenceKey for passing container width to parent for adaptive font sizing.
struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
