//
//  OnboardingStepIndicator.swift
//  Tenra
//
//  Liquid-Glass-capsule step indicator. Shows one SF Symbol per step,
//  with the current step tinted and the rest in a faded state.
//

import SwiftUI

struct OnboardingStepIndicator: View {
    /// 1-based current step index.
    let currentStep: Int

    private struct StepDef {
        let symbol: String
    }

    private static let steps: [StepDef] = [
        StepDef(symbol: "dollarsign.circle.fill"),
        StepDef(symbol: "creditcard.fill"),
        StepDef(symbol: "square.grid.2x2.fill"),
    ]

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(Self.steps.indices, id: \.self) { idx in
                stepIcon(at: idx)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .modifier(GlassCapsuleModifier())
        .animation(AppAnimation.contentSpring, value: currentStep)
    }

    @ViewBuilder
    private func stepIcon(at index: Int) -> some View {
        let stepNumber = index + 1
        let isActive = stepNumber == currentStep
        let isCompleted = stepNumber < currentStep

        Image(systemName: Self.steps[index].symbol)
            .font(.system(size: 16, weight: isActive ? .semibold : .regular))
            .foregroundStyle(
                isActive
                    ? AnyShapeStyle(AppColors.accent.gradient)
                    : isCompleted
                        ? AnyShapeStyle(AppColors.accent.opacity(0.55))
                        : AnyShapeStyle(AppColors.textSecondary.opacity(0.4))
            )
            .scaleEffect(isActive ? 1.15 : 1)
            .frame(width: 24, height: 24)
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(
                    Capsule()
                        .fill(AppColors.textSecondary.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(AppColors.textSecondary.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

#Preview("Onboarding Step Indicator") {
    VStack(spacing: AppSpacing.lg) {
        OnboardingStepIndicator(currentStep: 1)
        OnboardingStepIndicator(currentStep: 2)
        OnboardingStepIndicator(currentStep: 3)
    }
    .padding()
}
