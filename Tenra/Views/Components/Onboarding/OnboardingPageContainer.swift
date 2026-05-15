//
//  OnboardingPageContainer.swift
//  Tenra
//
//  Shared layout for onboarding data-collection steps:
//  step indicator lives in the navigation toolbar (principal slot),
//  title + subtitle sit above the body content, primary CTA pinned at the bottom.
//

import SwiftUI

struct OnboardingPageContainer<Content: View>: View {
    let progressStep: Int            // 1, 2, or 3
    let title: String
    let subtitle: String?
    let primaryButtonTitle: String
    let primaryButtonEnabled: Bool
    let onPrimaryTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button(action: onPrimaryTap) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!primaryButtonEnabled)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .principal) {
                OnboardingStepIndicator(currentStep: progressStep)
            }
        }
    }
}

#Preview("Onboarding Page Container") {
    NavigationStack {
        OnboardingPageContainer(
            progressStep: 2,
            title: "Step title goes here",
            subtitle: "Short supporting copy that explains the step.",
            primaryButtonTitle: "Next",
            primaryButtonEnabled: true,
            onPrimaryTap: {}
        ) {
            Text("Body content")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}
