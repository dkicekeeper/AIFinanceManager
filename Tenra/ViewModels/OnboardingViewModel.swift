//
//  OnboardingViewModel.swift
//  Tenra
//
//  Ephemeral state and commit pipeline for the first-launch onboarding flow.
//

import Foundation
import SwiftUI
import Observation
import os

/// Every screen in the onboarding flow — welcome carousel + data-collection steps.
enum OnboardingScreen: Int, CaseIterable {
    case welcome1, welcome2, welcome3, currency, account, categories
}

/// Direction of a screen change — drives which way the transition slides.
enum TransitionDirection {
    case forward, back
}

/// Draft for the first account being created during onboarding.
struct AccountDraft: Equatable {
    var name: String = ""
    var iconSource: IconSource = .sfSymbol("creditcard.fill")
    var balance: Double = 0
}

@Observable
@MainActor
final class OnboardingViewModel {
    // MARK: - Dependencies

    @ObservationIgnored private weak var coordinator: AppCoordinator?
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "Onboarding")

    // MARK: - Welcome carousel

    /// The currently displayed onboarding screen. Single source of navigation truth.
    var currentScreen: OnboardingScreen = .welcome1

    /// Direction of the most recent screen change — read by the transition.
    var transitionDirection: TransitionDirection = .forward

    // MARK: - Step state

    /// Step 1: chosen base currency. Default `KZT` (matches `AppSettings.defaultCurrency`).
    var draftCurrency: String = AppSettings.defaultCurrency

    /// Step 2: account form draft.
    var draftAccount: AccountDraft = AccountDraft()

    /// Set to the created account's id once Step 2 is committed for the first time.
    /// Subsequent re-entries update the existing account in place.
    var createdAccountId: String?

    /// Step 3: preset list with toggle state. All selected by default.
    var draftCategories: [SelectablePreset] = CategoryPreset.defaultExpense.map {
        $0.makeSelectable(isSelected: true)
    }

    /// True while the final commit pipeline is running (disables the Done button).
    var isFinishing: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Test-only convenience: builds a VM with no coordinator. The commit pipeline
    /// is a no-op in this mode (just toggles state). All draft logic still works.
    static func makeForTesting() -> OnboardingViewModel {
        OnboardingViewModel()
    }

    private init() {
        self.coordinator = nil
    }

    // MARK: - Derived UI helpers

    var selectedPresetCount: Int {
        draftCategories.lazy.filter { $0.isSelected }.count
    }

    var canAdvanceFromAccountStep: Bool {
        !draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFinish: Bool {
        selectedPresetCount > 0 && !isFinishing
    }

    // MARK: - Step navigation

    /// Advance to `screen` with a forward (slide-in-from-trailing) transition.
    func goForward(to screen: OnboardingScreen) {
        transitionDirection = .forward
        withAnimation(AppAnimation.onboardingTransition) {
            currentScreen = screen
        }
    }

    /// Return to `screen` with a back (slide-in-from-leading) transition.
    func goBack(to screen: OnboardingScreen) {
        transitionDirection = .back
        withAnimation(AppAnimation.onboardingTransition) {
            currentScreen = screen
        }
    }

    func startDataCollection() {
        goForward(to: .currency)
        logger.info("onboarding_started")
    }

    func advanceToAccountStep() async {
        guard let coordinator else { return }
        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        goForward(to: .account)
        logger.info("onboarding_step_completed step=currency currency=\(self.draftCurrency, privacy: .public)")
    }

    func advanceToCategoriesStep() async {
        guard let coordinator else { return }
        let trimmedName = draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingId = createdAccountId,
           let existing = coordinator.accountsViewModel.accounts.first(where: { $0.id == existingId }) {
            // Update branch — user came back to this step.
            var updated = existing
            updated.name = trimmedName
            updated.iconSource = draftAccount.iconSource
            updated.initialBalance = draftAccount.balance
            updated.balance = draftAccount.balance
            coordinator.accountsViewModel.updateAccount(updated)
        } else {
            await coordinator.accountsViewModel.addAccount(
                name: trimmedName,
                initialBalance: draftAccount.balance,
                currency: draftCurrency,
                iconSource: draftAccount.iconSource,
                shouldCalculateFromTransactions: false
            )
            // Last-added account id (AccountsViewModel appends to the end of the array).
            createdAccountId = coordinator.accountsViewModel.accounts.last?.id
        }
        goForward(to: .categories)
        logger.info("onboarding_step_completed step=account")
    }

    // MARK: - Final commit

    func finish() {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        for selectable in draftCategories where selectable.isSelected {
            let preset = selectable.preset
            let category = CustomCategory(
                name: String(localized: String.LocalizationValue(preset.nameKey)),
                iconSource: preset.iconSource,
                colorHex: preset.colorHex,
                type: preset.type
            )
            coordinator.categoriesViewModel.addCategory(category)
        }

        coordinator.completeOnboarding()
        logger.info("onboarding_finished selectedCount=\(self.selectedPresetCount, privacy: .public)")
    }
}
