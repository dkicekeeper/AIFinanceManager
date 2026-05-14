//
//  OnboardingTransition.swift
//  Tenra
//
//  Custom asymmetric transition for onboarding screen changes. The incoming
//  screen slides + scales in from one edge; the outgoing screen slides + scales
//  out the opposite edge. Edge direction is driven by `TransitionDirection`.
//  The spring overshoot comes from `AppAnimation.onboardingTransition`, applied
//  by the caller via `withAnimation`.
//

import SwiftUI

extension AnyTransition {
    static func onboardingStep(direction: TransitionDirection) -> AnyTransition {
        let insertionEdge: Edge = direction == .forward ? .trailing : .leading
        let removalEdge: Edge = direction == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge)
                .combined(with: .scale(scale: 0.88))
                .combined(with: .opacity),
            removal: .move(edge: removalEdge)
                .combined(with: .scale(scale: 0.88))
                .combined(with: .opacity)
        )
    }
}
