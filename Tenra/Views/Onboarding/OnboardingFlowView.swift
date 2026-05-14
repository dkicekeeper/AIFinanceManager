//
//  OnboardingFlowView.swift
//  Tenra
//
//  Root view of the onboarding experience. Renders one OnboardingScreen at a
//  time inside a ZStack, with a custom spring-overshoot transition on every
//  screen change.
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var vm: OnboardingViewModel

    init(coordinator: AppCoordinator) {
        _vm = State(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()
            screenContent
                .id(vm.currentScreen)
                .transition(.onboardingStep(direction: vm.transitionDirection))
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch vm.currentScreen {
        case .welcome1:
            OnboardingWelcomePage(
                pageIndex: 0,
                sfSymbol: "chart.pie.fill",
                title: String(localized: "onboarding.welcome.page1.title"),
                subtitle: String(localized: "onboarding.welcome.page1.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.next"),
                onPrimary: { vm.goForward(to: .welcome2) },
                onBack: nil
            )
        case .welcome2:
            OnboardingWelcomePage(
                pageIndex: 1,
                sfSymbol: "mic.fill",
                title: String(localized: "onboarding.welcome.page2.title"),
                subtitle: String(localized: "onboarding.welcome.page2.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.next"),
                onPrimary: { vm.goForward(to: .welcome3) },
                onBack: { vm.goBack(to: .welcome1) }
            )
        case .welcome3:
            OnboardingWelcomePage(
                pageIndex: 2,
                sfSymbol: "lock.shield.fill",
                title: String(localized: "onboarding.welcome.page3.title"),
                subtitle: String(localized: "onboarding.welcome.page3.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.start"),
                onPrimary: { vm.startDataCollection() },
                onBack: { vm.goBack(to: .welcome2) }
            )
        case .currency:
            OnboardingCurrencyStep(vm: vm)
        case .account:
            OnboardingAccountStep(vm: vm)
        case .categories:
            OnboardingCategoriesStep(vm: vm)
        }
    }
}
