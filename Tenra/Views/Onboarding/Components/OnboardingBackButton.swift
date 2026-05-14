//
//  OnboardingBackButton.swift
//  Tenra
//
//  Shared leading back-chevron used by onboarding screens (welcome carousel
//  and data-collection steps).
//

import SwiftUI

struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .accessibilityLabel(Text("Back"))
    }
}
