//
//  TransactionPaginationManager.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Combine

/// Manages pagination for large transaction lists
/// Loads transactions incrementally to improve performance
@MainActor
class TransactionPaginationManager: ObservableObject {
    // MARK: - Published Properties

    /// Currently visible date sections with their transactions
    @Published private(set) var visibleSections: [String] = []

    /// Grouped transactions by date key
    @Published private(set) var groupedTransactions: [String: [Transaction]] = [:]

    /// Whether there are more sections to load
    @Published private(set) var hasMore = true

    /// Whether currently loading more data
    @Published private(set) var isLoadingMore = false

    // MARK: - Private Properties

    /// All available date keys in sorted order
    private var allSortedKeys: [String] = []

    /// All grouped transactions (source of truth)
    private var allGroupedTransactions: [String: [Transaction]] = [:]

    /// Number of date sections to load per page
    private let sectionsPerPage = 10

    /// Current page index
    private var currentPage = 0

    // MARK: - Initialization

    init() {
        print("📄 [PAGINATION] TransactionPaginationManager initialized")
    }

    // MARK: - Public Methods

    /// Initialize pagination with grouped transactions
    /// - Parameters:
    ///   - grouped: Dictionary of date keys to transactions
    ///   - sortedKeys: Array of date keys in display order
    func initialize(grouped: [String: [Transaction]], sortedKeys: [String]) {
        print("📄 [PAGINATION] Initializing with \(sortedKeys.count) sections, \(grouped.values.flatMap { $0 }.count) total transactions")

        self.allGroupedTransactions = grouped
        self.allSortedKeys = sortedKeys
        self.currentPage = 0
        self.visibleSections = []
        self.groupedTransactions = [:]
        self.hasMore = !sortedKeys.isEmpty

        // Load first page immediately
        loadNextPage()
    }

    /// Load the next page of transaction sections
    func loadNextPage() {
        guard hasMore && !isLoadingMore else {
            print("📄 [PAGINATION] Skip loading: hasMore=\(hasMore), isLoadingMore=\(isLoadingMore)")
            return
        }

        isLoadingMore = true
        print("📄 [PAGINATION] Loading page \(currentPage + 1)")

        // Calculate range for next page
        let startIndex = currentPage * sectionsPerPage
        let endIndex = min(startIndex + sectionsPerPage, allSortedKeys.count)

        guard startIndex < allSortedKeys.count else {
            print("📄 [PAGINATION] No more sections to load")
            hasMore = false
            isLoadingMore = false
            return
        }

        // Get next batch of sections
        let newSections = Array(allSortedKeys[startIndex..<endIndex])
        print("📄 [PAGINATION] Loading sections \(startIndex)..<\(endIndex): \(newSections)")

        // Add new sections to visible list
        visibleSections.append(contentsOf: newSections)

        // Add corresponding transactions to grouped dictionary
        for section in newSections {
            if let transactions = allGroupedTransactions[section] {
                groupedTransactions[section] = transactions
            }
        }

        // Update state
        currentPage += 1
        hasMore = endIndex < allSortedKeys.count
        isLoadingMore = false

        let totalVisibleTransactions = groupedTransactions.values.flatMap { $0 }.count
        print("📄 [PAGINATION] Page loaded. Visible: \(visibleSections.count) sections, \(totalVisibleTransactions) transactions. HasMore: \(hasMore)")
    }

    /// Reset pagination to initial state
    func reset() {
        print("📄 [PAGINATION] Resetting pagination")
        currentPage = 0
        visibleSections = []
        groupedTransactions = [:]
        hasMore = !allSortedKeys.isEmpty
        isLoadingMore = false
    }

    /// Check if should load more when reaching a specific section
    /// - Parameter sectionKey: The date key of the section
    /// - Returns: True if this is near the end and should trigger loading
    func shouldLoadMore(for sectionKey: String) -> Bool {
        // Load more when reaching the last 3 visible sections
        guard let index = visibleSections.firstIndex(of: sectionKey) else {
            return false
        }

        let triggerIndex = max(0, visibleSections.count - 3)
        let shouldLoad = index >= triggerIndex && hasMore && !isLoadingMore

        if shouldLoad {
            print("📄 [PAGINATION] Trigger loading at section \(sectionKey) (index \(index)/\(visibleSections.count))")
        }

        return shouldLoad
    }
}
