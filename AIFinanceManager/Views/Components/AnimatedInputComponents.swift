//
//  AnimatedInputComponents.swift
//  AIFinanceManager
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Shared building blocks for animated text/amount input:
//  - AnimatedChar: character data model with animation state tracking
//  - CharAnimState: keyframe animation value type
//  - AnimatedTitleChar: spring + wobble character animation (keyframeAnimator)
//  - BlinkingCursor: blinking insertion point indicator
//

import SwiftUI

// MARK: - AnimatedChar

/// Data model for a single animated character
struct AnimatedChar: Identifiable {
    let id: UUID
    let character: Character
    var isNew: Bool
}

// MARK: - CharAnimState

/// Keyframe animation state for AnimatedTitleChar.
struct CharAnimState {
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0
    var rotation: Double = 0
}

// MARK: - AnimatedTitleChar

/// Renders a single text character with spring entrance + wobble effect.
/// Uses keyframeAnimator (iOS 17+) instead of DispatchQueue.asyncAfter.
struct AnimatedTitleChar: View {
    let character: Character
    let isNew: Bool
    let font: Font
    let color: Color

    @State private var animTrigger = false

    var body: some View {
        Text(String(character))
            .font(font)
            .foregroundStyle(color)
            .keyframeAnimator(
                initialValue: CharAnimState(),
                trigger: animTrigger
            ) { content, value in
                content
                    .offset(y: value.offsetY)
                    .scaleEffect(value.scale)
                    .rotationEffect(.degrees(value.rotation))
            } keyframes: { _ in
                KeyframeTrack(\.offsetY) {
                    LinearKeyframe(20, duration: 0)
                    SpringKeyframe(0, duration: 0.4, spring: .init(response: 0.4, dampingRatio: 0.6))
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.5, duration: 0)
                    SpringKeyframe(1.0, duration: 0.4, spring: .init(response: 0.4, dampingRatio: 0.6))
                }
                KeyframeTrack(\.rotation) {
                    LinearKeyframe(0, duration: 0.1)
                    SpringKeyframe(8,  duration: 0.15, spring: .init(response: 0.15, dampingRatio: 0.3))
                    SpringKeyframe(-8, duration: 0.15, spring: .init(response: 0.15, dampingRatio: 0.3))
                    SpringKeyframe(4,  duration: 0.15, spring: .init(response: 0.15, dampingRatio: 0.3))
                    SpringKeyframe(0,  duration: 0.15, spring: .init(response: 0.15, dampingRatio: 0.3))
                }
            }
            .onAppear {
                if isNew { animTrigger.toggle() }
            }
            .onChange(of: isNew) { _, new in
                if new { animTrigger.toggle() }
            }
            .onChange(of: character) { _, _ in
                animTrigger.toggle()
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
