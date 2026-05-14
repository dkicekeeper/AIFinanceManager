//
//  OnboardingWelcomePage.swift
//  Tenra
//
//  One self-contained welcome-carousel screen: optional back chevron, hero
//  icon + copy, page dots, and the primary CTA.
//

import SwiftUI

struct OnboardingWelcomePage: View {
    let pageIndex: Int
    let sfSymbol: String
    let title: String
    let subtitle: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)

            Spacer()

            Image(systemName: sfSymbol)
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(AppColors.accent)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.top, AppSpacing.lg)

            Spacer()

            OnboardingDotsIndicator(currentIndex: pageIndex, totalCount: 3)
                .padding(.bottom, AppSpacing.lg)

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }
}
