//
//  TransactionGroupingService.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: TransactionsViewModel Decomposition
//

import Foundation

/// Service responsible for grouping and sorting transactions
/// Extracted from TransactionsViewModel to improve separation of concerns
class TransactionGroupingService {

    // MARK: - Properties

    private let dateFormatter: DateFormatter
    private let displayDateFormatter: DateFormatter
    private let displayDateWithYearFormatter: DateFormatter

    // MARK: - Initialization

    init(
        dateFormatter: DateFormatter,
        displayDateFormatter: DateFormatter,
        displayDateWithYearFormatter: DateFormatter
    ) {
        self.dateFormatter = dateFormatter
        self.displayDateFormatter = displayDateFormatter
        self.displayDateWithYearFormatter = displayDateWithYearFormatter
    }

    // MARK: - Grouping by Date

    /// Group transactions by date with formatted date keys
    /// - Parameters:
    ///   - transactions: Array of transactions to group
    /// - Returns: Tuple containing grouped dictionary and sorted keys
    func groupByDate(_ transactions: [Transaction]) -> (grouped: [String: [Transaction]], sortedKeys: [String]) {
        var grouped: [String: [Transaction]] = [:]

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        // Separate and sort transactions
        let (recurringTransactions, regularTransactions) = separateAndSortTransactions(transactions)
        let allTransactions = recurringTransactions + regularTransactions

        // Group by date with proper formatting
        for transaction in allTransactions {
            guard let date = dateFormatter.date(from: transaction.date) else { continue }

            let dateKey = formatDateKey(date: date, currentYear: currentYear, calendar: calendar)
            grouped[dateKey, default: []].append(transaction)
        }

        // Sort keys by date descending (most recent first)
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            // Parse dates from formatted keys
            let date1 = parseDateFromKey(key1, currentYear: currentYear)
            let date2 = parseDateFromKey(key2, currentYear: currentYear)
            return date1 > date2
        }

        return (grouped, sortedKeys)
    }

    /// Group transactions by month
    /// - Parameters:
    ///   - transactions: Array of transactions to group
    /// - Returns: Dictionary with month keys (yyyy-MM) and transaction arrays
    func groupByMonth(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var grouped: [String: [Transaction]] = [:]
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"

        for transaction in transactions {
            guard let date = dateFormatter.date(from: transaction.date) else { continue }
            let monthKey = monthFormatter.string(from: date)
            grouped[monthKey, default: []].append(transaction)
        }

        return grouped
    }

    /// Group transactions by category
    /// - Parameters:
    ///   - transactions: Array of transactions to group
    /// - Returns: Dictionary with category keys and transaction arrays
    func groupByCategory(_ transactions: [Transaction]) -> [String: [Transaction]] {
        var grouped: [String: [Transaction]] = [:]

        for transaction in transactions {
            grouped[transaction.category, default: []].append(transaction)
        }

        return grouped
    }

    // MARK: - Sorting

    /// Sort transactions by date descending (most recent first)
    /// - Parameters:
    ///   - transactions: Array of transactions to sort
    /// - Returns: Sorted array of transactions
    func sortByDateDescending(_ transactions: [Transaction]) -> [Transaction] {
        return transactions.sorted { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 > date2
        }
    }

    /// Sort transactions by creation time descending
    /// - Parameters:
    ///   - transactions: Array of transactions to sort
    /// - Returns: Sorted array of transactions
    func sortByCreatedAtDescending(_ transactions: [Transaction]) -> [Transaction] {
        return transactions.sorted { tx1, tx2 in
            if tx1.createdAt != tx2.createdAt {
                return tx1.createdAt > tx2.createdAt
            }
            return tx1.id > tx2.id
        }
    }

    // MARK: - Recurring Transaction Handling

    /// Get only the nearest transaction for each recurring series
    /// Useful for showing a single representative transaction per series
    /// - Parameters:
    ///   - transactions: Array of transactions to process
    /// - Returns: Array with only nearest recurring transactions
    func getNearestRecurringTransactions(_ transactions: [Transaction]) -> [Transaction] {
        var transactionsBySeries: [String: [Transaction]] = [:]

        // Group by series ID
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                transactionsBySeries[seriesId, default: []].append(transaction)
            }
        }

        var result: [Transaction] = []

        // Get nearest transaction for each series
        for (_, seriesTransactions) in transactionsBySeries {
            let transactionsWithDates = seriesTransactions.compactMap { transaction -> (Transaction, Date)? in
                guard let date = dateFormatter.date(from: transaction.date) else {
                    return nil
                }
                return (transaction, date)
            }

            if let nearest = transactionsWithDates.min(by: { $0.1 < $1.1 })?.0 {
                result.append(nearest)
            }
        }

        return result
    }

    /// Separate transactions into recurring and regular, then sort appropriately
    /// - Parameters:
    ///   - transactions: Array of transactions to process
    /// - Returns: Tuple of (recurring sorted by date, regular sorted by createdAt)
    func separateAndSortTransactions(_ transactions: [Transaction]) -> (recurring: [Transaction], regular: [Transaction]) {
        var recurringTransactions: [Transaction] = []
        var regularTransactions: [Transaction] = []

        // Separate
        for transaction in transactions {
            if transaction.recurringSeriesId != nil {
                recurringTransactions.append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }

        // Sort recurring by date ascending
        recurringTransactions.sort { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 < date2
        }

        // Sort regular by createdAt descending
        regularTransactions.sort { tx1, tx2 in
            if tx1.createdAt != tx2.createdAt {
                return tx1.createdAt > tx2.createdAt
            }
            return tx1.id > tx2.id
        }

        return (recurringTransactions, regularTransactions)
    }

    // MARK: - Private Helpers

    private func formatDateKey(date: Date, currentYear: Int, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: Date())
        let transactionDay = calendar.startOfDay(for: date)

        if transactionDay == today {
            return String(localized: "date.today")
        } else if calendar.dateComponents([.day], from: transactionDay, to: today).day == 1 {
            return String(localized: "date.yesterday")
        } else {
            let transactionYear = calendar.component(.year, from: date)
            if transactionYear == currentYear {
                return displayDateFormatter.string(from: date)
            } else {
                return displayDateWithYearFormatter.string(from: date)
            }
        }
    }

    private func parseDateFromKey(_ key: String, currentYear: Int) -> Date {
        // Handle localized special keys
        let todayKey = String(localized: "date.today")
        let yesterdayKey = String(localized: "date.yesterday")

        if key == todayKey {
            return Date()
        } else if key == yesterdayKey {
            return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        }

        // Try to parse with year
        if let date = displayDateWithYearFormatter.date(from: key) {
            return date
        }

        // Try to parse without year (assume current year)
        if let date = displayDateFormatter.date(from: key) {
            var components = Calendar.current.dateComponents([.month, .day], from: date)
            components.year = currentYear
            return Calendar.current.date(from: components) ?? date
        }

        return Date.distantPast
    }
}
