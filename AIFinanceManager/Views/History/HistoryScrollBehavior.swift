//
//  HistoryScrollBehavior.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: HistoryView Decomposition
//
//  Pure logic for determining scroll target in transaction history.
//  Extracted to improve testability and maintainability.
//

import Foundation

/// Contains pure logic for determining scroll behavior in history view
struct HistoryScrollBehavior {

    // MARK: - Public Methods

    /// Find the appropriate section to scroll to on initial load
    /// Prioritizes: Today > Yesterday > First past section > First section
    ///
    /// - Parameters:
    ///   - sections: Array of date section keys in display order
    ///   - grouped: Dictionary of transactions grouped by date key
    ///   - todayKey: Localized "Today" key
    ///   - yesterdayKey: Localized "Yesterday" key
    ///   - dateFormatter: DateFormatter for parsing transaction dates
    /// - Returns: Section key to scroll to, or nil if no sections
    static func findScrollTarget(
        sections: [String],
        grouped: [String: [Transaction]],
        todayKey: String,
        yesterdayKey: String,
        dateFormatter: DateFormatter
    ) -> String? {
        guard !sections.isEmpty else {
            return nil
        }

        // Priority 1: Check if "Today" section exists
        if sections.contains(todayKey) {
            #if DEBUG
            #endif
            return todayKey
        }

        // Priority 2: Check if "Yesterday" section exists
        if sections.contains(yesterdayKey) {
            #if DEBUG
            #endif
            return yesterdayKey
        }

        // Priority 3: Find first past (non-future) section
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for key in sections {
            // Skip already checked special keys
            if key == todayKey || key == yesterdayKey {
                continue
            }

            // Check if this section contains past transactions
            if let transactions = grouped[key],
               let firstTransaction = transactions.first,
               let date = dateFormatter.date(from: firstTransaction.date) {
                let transactionDay = calendar.startOfDay(for: date)

                // If transaction is today or in the past, this is our target
                if transactionDay <= today {
                    #if DEBUG
                    #endif
                    return key
                }
            }
        }

        // Priority 4: Fallback to first section (might be future)
        let fallback = sections.first
        #if DEBUG
        #endif
        return fallback
    }

    /// Determine if a section represents a future date
    ///
    /// - Parameters:
    ///   - key: Date section key
    ///   - transactions: Transactions in this section
    ///   - todayKey: Localized "Today" key
    ///   - yesterdayKey: Localized "Yesterday" key
    ///   - dateFormatter: DateFormatter for parsing transaction dates
    /// - Returns: True if section contains future transactions
    static func isFutureSection(
        key: String,
        transactions: [Transaction],
        todayKey: String,
        yesterdayKey: String,
        dateFormatter: DateFormatter
    ) -> Bool {
        // Today and Yesterday are not future
        if key == todayKey || key == yesterdayKey {
            return false
        }

        // Check first transaction date
        guard let firstTransaction = transactions.first,
              let date = dateFormatter.date(from: firstTransaction.date) else {
            return false
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let transactionDay = calendar.startOfDay(for: date)

        return transactionDay > today
    }

    /// Calculate scroll delay based on data size
    /// Larger datasets need more time to load before scrolling
    ///
    /// - Parameter sectionCount: Number of sections to display
    /// - Returns: Delay in nanoseconds
    static func calculateScrollDelay(sectionCount: Int) -> UInt64 {
        // Base delay: 150ms
        let baseDelay: UInt64 = 150_000_000

        // Add 10ms per 100 sections (max +50ms)
        let additionalDelay = min(UInt64(sectionCount / 100) * 10_000_000, 50_000_000)

        return baseDelay + additionalDelay
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Get debug information about scroll decision
    static func debugScrollTarget(
        sections: [String],
        grouped: [String: [Transaction]],
        target: String?,
        todayKey: String,
        yesterdayKey: String
    ) -> String {
        guard let target = target else {
            return "No scroll target (empty sections)"
        }

        var info = "Scroll target: \(target)\n"
        info += "Total sections: \(sections.count)\n"
        info += "Has Today: \(sections.contains(todayKey))\n"
        info += "Has Yesterday: \(sections.contains(yesterdayKey))\n"

        if let transactions = grouped[target] {
            info += "Target transactions: \(transactions.count)\n"
        }

        return info
    }
    #endif
}
