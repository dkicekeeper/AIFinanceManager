//
//  ContentRevealModifier.swift
//  Tenra
//
//  Lightweight modifier that fades content in when data is ready.
//  Replaces SkeletonLoadingModifier — preserves view identity (no if/else branching).
//

import SwiftUI

// MARK: - ContentRevealModifier

/// Fades content in when `isReady` becomes true.
/// Optional `delay` staggers multiple sections so they don't all appear in the same frame.
struct ContentRevealModifier: ViewModifier {
    let isReady: Bool
    var delay: Double = 0

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(AppAnimation.contentRevealAnimation, value: isVisible)
            // `.task(id: isReady)` replaces the unstructured `Task { sleep }` that the
            // old `revealAfterDelay()` spawned: that task was unowned and could write
            // `isVisible = true` after the view had already disappeared. `.task` is
            // tied to view lifetime and auto-cancels on disappear.
            .task(id: isReady) {
                guard isReady, !isVisible else { return }
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    if Task.isCancelled { return }
                }
                isVisible = true
            }
    }
}

// MARK: - View Extension

extension View {
    /// Hides this view until `isReady` is true, then fades it in.
    /// Use `delay` to stagger multiple sections for a smooth cascading reveal.
    func contentReveal(isReady: Bool, delay: Double = 0) -> some View {
        modifier(ContentRevealModifier(isReady: isReady, delay: delay))
    }
}
