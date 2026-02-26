//
//  HomePersistentState.swift
//  AIFinanceManager
//
//  Persistent UI state for the Home screen that survives tab-bar reconstruction.
//  When the user taps +/× in MainTabView, the conditional tab declarations cause
//  ContentView to be destroyed and recreated. Storing critical state here (in
//  MainTabView's @State) keeps it alive across those reconstructions.
//

import SwiftUI

/// Holds the home screen's volatile UI state that must survive ContentView recreation.
/// - Stored as `@State` in MainTabView (always alive).
/// - Injected into ContentView via `.environment(homeState)`.
@Observable
@MainActor
final class HomePersistentState {
    /// Last computed transactions summary for the selected time filter.
    /// Nil only before the first computation completes.
    var cachedSummary: Summary? = nil

    /// Guards expensive first-appear work in ContentView.
    /// Once true, back-navigation re-appearances are cheap.
    var hasAppearedOnce: Bool = false

    /// Decoded wallpaper image (downsampled to screen resolution).
    /// UIImage is a class — changes propagate via @Observable automatically.
    var wallpaperImage: UIImage? = nil
}
