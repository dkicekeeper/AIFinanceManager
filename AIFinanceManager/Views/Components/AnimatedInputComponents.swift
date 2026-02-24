//
//  AnimatedInputComponents.swift
//  AIFinanceManager
//
//  Created: Phase 16 - AnimatedHeroInput
//
//  Shared building blocks for animated text/amount input:
//  - BlinkingCursor: blinking insertion point indicator
//

import SwiftUI

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
