//
//  OnboardingStateTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct OnboardingStateTests {
    private let testKey = "hasCompletedOnboarding"

    @Test func defaultsToNotCompleted() {
        UserDefaults.standard.removeObject(forKey: testKey)
        #expect(OnboardingState.isCompleted == false)
    }

    @Test func markCompletedFlipsTheFlag() {
        UserDefaults.standard.removeObject(forKey: testKey)
        OnboardingState.markCompleted()
        #expect(OnboardingState.isCompleted == true)
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test func resetClearsTheFlag() {
        OnboardingState.markCompleted()
        #expect(OnboardingState.isCompleted == true)
        OnboardingState.reset()
        #expect(OnboardingState.isCompleted == false)
    }
}
