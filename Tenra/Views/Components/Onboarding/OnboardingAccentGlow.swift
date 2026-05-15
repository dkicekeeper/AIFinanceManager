//
//  OnboardingAccentGlow.swift
//  Tenra
//
//  Ambient accent-coloured glow rising from the bottom edge of the screen,
//  used as the background for onboarding screens. Implemented with a blurred
//  gradient-filled circle offset just below the visible area.
//

import SwiftUI

extension View {
    /// Soft accent-tinted glow rising from the bottom edge. Designed to sit
    /// underneath onboarding content (toolbar + safe-area insets included).
    func onboardingAccentGlow(tint: Color = AppColors.accent) -> some View {
        background {
            Circle()
                .fill(tint.gradient)
                .visualEffect { content, proxy in
                    content.offset(y: proxy.size.height * 0.85)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .blur(radius: 120)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Onboarding Accent Glow") {
    NavigationStack {
        VStack {
            Text("Sample content")
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingAccentGlow()
    }
}
