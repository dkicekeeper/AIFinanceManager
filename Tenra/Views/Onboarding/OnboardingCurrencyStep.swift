//
//  OnboardingCurrencyStep.swift
//  Tenra
//

import SwiftUI

struct OnboardingCurrencyStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingPageContainer(
            progressStep: 1,
            title: String(localized: "onboarding.currency.title"),
            subtitle: String(localized: "onboarding.currency.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: true,
            onPrimaryTap: {
                Task { await vm.advanceToAccountStep() }
            }
        ) {
            CurrencyListContent(selectedCurrency: vm.draftCurrency) { code in
                vm.draftCurrency = code
            }
            .padding(.top, AppSpacing.md)
        }
        .navigationBarBackButtonHidden(false)
    }
}
