//
//  HistoryFilterCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: HistoryView Decomposition
//
//  Manages all filter state and debouncing logic for HistoryView.
//  Extracted to follow Single Responsibility Principle.
//

import Foundation
import SwiftUI
import Combine

/// Coordinates filter state and debouncing for HistoryView
/// Handles search text, account filter, and debouncing logic
@MainActor
class HistoryFilterCoordinator: ObservableObject {

    // MARK: - Published Properties

    /// Currently selected account filter (nil = all accounts)
    @Published var selectedAccountFilter: String?

    /// Current search text (user input)
    @Published var searchText: String = ""

    /// Debounced search text (used for actual filtering)
    @Published var debouncedSearchText: String = ""

    /// Whether search is currently active
    @Published var isSearchActive: Bool = false

    /// Whether category filter sheet is shown
    @Published var showingCategoryFilter: Bool = false

    // MARK: - Private Properties

    /// Task for debouncing search input
    private var searchTask: Task<Void, Never>?

    /// Task for debouncing filter changes
    private var filterTask: Task<Void, Never>?

    /// Search debounce delay in nanoseconds (300ms)
    private let searchDebounceDelay: UInt64 = 300_000_000

    /// Filter debounce delay in nanoseconds (150ms)
    private let filterDebounceDelay: UInt64 = 150_000_000

    // MARK: - Initialization

    init() {
        setupObservers()
    }

    // MARK: - Public Methods

    /// Apply search text with debouncing
    /// - Parameter text: New search text
    func applySearch(_ text: String) {
        searchText = text

        // Cancel previous search task
        searchTask?.cancel()

        // Debounce search - update after 300ms of no changes
        searchTask = Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: self.searchDebounceDelay)
            guard !Task.isCancelled else { return }

            // Verify text hasn't changed during debounce
            if self.searchText == text {
                await MainActor.run {
                    self.debouncedSearchText = text
                    #if DEBUG
                    print("🔍 [FILTER] Search debounced: '\(text)'")
                    #endif
                }
            }
        }
    }

    /// Apply account filter with debouncing
    /// - Parameter accountId: Account ID to filter by (nil for all accounts)
    func applyAccountFilter(_ accountId: String?) {
        selectedAccountFilter = accountId
        HapticManager.selection()

        // Cancel previous filter task
        filterTask?.cancel()

        // Debounce filter - update after 150ms
        filterTask = Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: self.filterDebounceDelay)
            guard !Task.isCancelled else { return }

            #if DEBUG
            print("🔍 [FILTER] Account filter debounced: \(accountId ?? "all")")
            #endif
        }
    }

    /// Apply category filter change with debouncing
    /// Called when category selection changes
    func applyCategoryFilterChange() {
        HapticManager.selection()

        // Cancel previous filter task
        filterTask?.cancel()

        // Debounce filter - update after 150ms
        filterTask = Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(nanoseconds: self.filterDebounceDelay)
            guard !Task.isCancelled else { return }

            #if DEBUG
            print("🔍 [FILTER] Category filter debounced")
            #endif
        }
    }

    /// Reset all filters to default state
    func reset() {
        selectedAccountFilter = nil
        searchText = ""
        debouncedSearchText = ""
        isSearchActive = false
        showingCategoryFilter = false

        // Cancel pending tasks
        searchTask?.cancel()
        filterTask?.cancel()

        #if DEBUG
        print("🔍 [FILTER] All filters reset")
        #endif
    }

    /// Set initial account filter (from navigation)
    /// - Parameter accountId: Account ID to set
    func setInitialAccountFilter(_ accountId: String?) {
        if let accountId = accountId, selectedAccountFilter != accountId {
            selectedAccountFilter = accountId
            #if DEBUG
            print("🔍 [FILTER] Initial account filter set: \(accountId)")
            #endif
        }
    }

    // MARK: - Private Methods

    /// Setup internal observers for automatic debouncing
    private func setupObservers() {
        // This method can be extended in future for additional logic
        // Currently, debouncing is handled explicitly in apply methods
    }

    /// Cancel all pending debounce tasks
    func cancelPendingTasks() {
        searchTask?.cancel()
        filterTask?.cancel()
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Get current filter state for debugging
    func getFilterState() -> [String: Any] {
        return [
            "selectedAccount": selectedAccountFilter ?? "all",
            "searchText": searchText,
            "debouncedSearchText": debouncedSearchText,
            "isSearchActive": isSearchActive,
            "showingCategoryFilter": showingCategoryFilter
        ]
    }

    /// Check if any filters are active
    var hasActiveFilters: Bool {
        return selectedAccountFilter != nil ||
               !debouncedSearchText.isEmpty
    }
    #endif
}
