//
//  OnboardingFlowView.swift
//  Tenra
//
//  Root view of the onboarding experience: welcome carousel followed by a
//  NavigationStack-driven 3-step data collection flow.
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var vm: OnboardingViewModel
    @State private var hasStartedDataCollection = false

    init(coordinator: AppCoordinator) {
        _vm = State(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        if hasStartedDataCollection {
            NavigationStack(path: $vm.path) {
                OnboardingCurrencyStep(vm: vm)
                    .navigationDestination(for: OnboardingStep.self) { step in
                        switch step {
                        case .currency:
                            OnboardingCurrencyStep(vm: vm)
                        case .account:
                            OnboardingAccountStep(vm: vm)
                        case .categories:
                            OnboardingCategoriesStep(vm: vm)
                        }
                    }
            }
        } else {
            welcomeCarousel
        }
    }

    @ViewBuilder
    private var welcomeCarousel: some View {
        VStack(spacing: 0) {
            TabView(selection: $vm.welcomePage) {
                OnboardingWelcomePage(
                    sfSymbol: "chart.pie.fill",
                    title: String(localized: "onboarding.welcome.page1.title"),
                    subtitle: String(localized: "onboarding.welcome.page1.subtitle")
                )
                .tag(0)

                OnboardingWelcomePage(
                    sfSymbol: "mic.fill",
                    title: String(localized: "onboarding.welcome.page2.title"),
                    subtitle: String(localized: "onboarding.welcome.page2.subtitle")
                )
                .tag(1)

                OnboardingWelcomePage(
                    sfSymbol: "lock.shield.fill",
                    title: String(localized: "onboarding.welcome.page3.title"),
                    subtitle: String(localized: "onboarding.welcome.page3.subtitle")
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: handlePrimaryTap) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }

    private var primaryTitle: String {
        vm.welcomePage == 2
            ? String(localized: "onboarding.cta.start")
            : String(localized: "onboarding.cta.next")
    }

    private func handlePrimaryTap() {
        if vm.welcomePage < 2 {
            withAnimation(AppAnimation.contentSpring) {
                vm.welcomePage += 1
            }
        } else {
            vm.startDataCollection()
            withAnimation(AppAnimation.contentSpring) {
                hasStartedDataCollection = true
            }
        }
    }
}
