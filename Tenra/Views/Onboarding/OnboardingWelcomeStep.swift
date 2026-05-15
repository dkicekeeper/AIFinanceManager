//
//  OnboardingWelcomeStep.swift
//  Tenra
//
//  NavigationStack root for onboarding. Drives the icon-cycle via TimelineView
//  and stacks the synced title/subtitle just above the primary CTA so the
//  copy reads alongside the action, not floating under the hero.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    @Bindable var vm: OnboardingViewModel

    @State private var startDate: Date = .now
    @State private var phaseIndex: Int = 0

    private static let phases: [LoopOnBoardingPhase] = [
        LoopOnBoardingPhase(
            symbol: "chart.pie.fill",
            title: String(localized: "onboarding.welcome.page1.title"),
            subtitle: String(localized: "onboarding.welcome.page1.subtitle")
        ),
        LoopOnBoardingPhase(
            symbol: "mic.fill",
            title: String(localized: "onboarding.welcome.page2.title"),
            subtitle: String(localized: "onboarding.welcome.page2.subtitle")
        ),
        LoopOnBoardingPhase(
            symbol: "lock.shield.fill",
            title: String(localized: "onboarding.welcome.page3.title"),
            subtitle: String(localized: "onboarding.welcome.page3.subtitle")
        ),
    ]

    private let config = LoopOnBoardingConfig()

    var body: some View {
        let timelineDuration = CGFloat(config.phaseUpdateAfter) * 3.0

        TimelineView(.periodic(from: startDate, by: timelineDuration)) { ctx in
            let diff = Int(startDate.distance(to: ctx.date)) / (config.phaseUpdateAfter * 3)
            let index = diff % Self.phases.count
            let phase = Self.phases[index]

            VStack(spacing: 0) {
                Spacer()

                LoopOnboardingHero(symbol: phase.symbol, config: config)

                Spacer()

                VStack(spacing: AppSpacing.sm) {
                    Text(phase.title)
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(phase.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)
                .id(index)
                .transition(LoopOnboardingTextTransition())
                .padding(.bottom, AppSpacing.xl)

                Button {
                    vm.startDataCollection()
                } label: {
                    Text(String(localized: "onboarding.cta.start"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: index)
            .sensoryFeedback(.selection, trigger: index)
            .onChange(of: index) { _, newValue in
                phaseIndex = newValue
            }
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Onboarding — Welcome") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingWelcomeStep(vm: vm)
    }
}
