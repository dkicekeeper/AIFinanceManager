//
//  OnboardingDotsIndicator.swift
//  Tenra
//
//  Page-dots indicator for the onboarding welcome carousel. Highlights the
//  CURRENT dot only — distinct from OnboardingProgressBar, which fills
//  cumulatively for the data-collection steps.
//

import SwiftUI

struct OnboardingDotsIndicator: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<totalCount, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex
                          ? AppColors.accent
                          : AppColors.textSecondary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(AppAnimation.contentSpring, value: currentIndex)
    }
}

#Preview {
    OnboardingDotsIndicator(currentIndex: 1, totalCount: 3)
        .padding()
}
