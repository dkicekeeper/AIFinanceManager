//
//  SkeletonLoadingModifier.swift
//  AIFinanceManager
//
//  Universal per-element skeleton loading modifier (Phase 30)

import SwiftUI

// MARK: - SkeletonLoadingModifier

/// Universal ViewModifier — shows skeleton when isLoading, transitions to real content when ready.
/// Usage: anyView.skeletonLoading(isLoading: flag) { SkeletonShape() }
struct SkeletonLoadingModifier<S: View>: ViewModifier {
    let isLoading: Bool
    @ViewBuilder let skeleton: () -> S

    init(isLoading: Bool, @ViewBuilder skeleton: @escaping () -> S) {
        self.isLoading = isLoading
        self.skeleton = skeleton
    }

    func body(content: Content) -> some View {
        Group {
            if isLoading {
                skeleton()
                    .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
            } else {
                content
                    .transition(.opacity.combined(with: .scale(1.02, anchor: .center)))
            }
        }
        .animation(.spring(response: 0.4), value: isLoading)
    }
}

extension View {
    /// Replaces this view with `skeleton()` while `isLoading` is true.
    /// Transitions smoothly to real content once loading completes.
    func skeletonLoading<S: View>(
        isLoading: Bool,
        @ViewBuilder skeleton: @escaping () -> S
    ) -> some View {
        modifier(SkeletonLoadingModifier(isLoading: isLoading, skeleton: skeleton))
    }
}
