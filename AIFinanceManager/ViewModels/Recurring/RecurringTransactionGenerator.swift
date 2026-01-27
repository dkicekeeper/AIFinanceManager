//
//  RecurringTransactionGenerator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: TransactionsViewModel Decomposition
//

import Foundation

/// Service responsible for generating recurring transactions
/// Extracted from TransactionsViewModel to improve separation of concerns
class RecurringTransactionGenerator {

    // MARK: - Properties

    private let dateFormatter: DateFormatter
    private let calendar: Calendar

    // MARK: - Initialization

    init(dateFormatter: DateFormatter, calendar: Calendar = .current) {
        self.dateFormatter = dateFormatter
        self.calendar = calendar
    }

    // MARK: - Transaction Generation

    /// Generate transactions for all active recurring series
    /// - Parameters:
    ///   - series: Array of recurring series
    ///   - existingOccurrences: Array of existing occurrences to avoid duplicates
    ///   - existingTransactionIds: Set of existing transaction IDs
    ///   - horizonMonths: Number of months to generate ahead (default: 3)
    /// - Returns: Tuple of (new transactions, new occurrences)
    func generateTransactions(
        series: [RecurringSeries],
        existingOccurrences: [RecurringOccurrence],
        existingTransactionIds: Set<String>,
        horizonMonths: Int = 3
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        let today = calendar.startOfDay(for: Date())
        guard let horizonDate = calendar.date(byAdding: .month, value: horizonMonths, to: today) else {
            return ([], [])
        }

        // Build set of existing occurrence keys
        var existingOccurrenceKeys: Set<String> = []
        for occurrence in existingOccurrences {
            existingOccurrenceKeys.insert("\(occurrence.seriesId):\(occurrence.occurrenceDate)")
        }

        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []

        // Generate for each active series
        for activeSeries in series where activeSeries.isActive {
            let (transactions, occurrences) = generateTransactionsForSeries(
                series: activeSeries,
                horizonDate: horizonDate,
                existingOccurrenceKeys: &existingOccurrenceKeys,
                existingTransactionIds: existingTransactionIds
            )

            newTransactions.append(contentsOf: transactions)
            newOccurrences.append(contentsOf: occurrences)
        }

        return (newTransactions, newOccurrences)
    }

    /// Generate transactions for a single recurring series
    /// - Parameters:
    ///   - series: The recurring series
    ///   - horizonDate: The date to generate up to
    ///   - existingOccurrenceKeys: Set of existing occurrence keys (modified in place)
    ///   - existingTransactionIds: Set of existing transaction IDs
    /// - Returns: Tuple of (transactions, occurrences) for this series
    private func generateTransactionsForSeries(
        series: RecurringSeries,
        horizonDate: Date,
        existingOccurrenceKeys: inout Set<String>,
        existingTransactionIds: Set<String>
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        guard let startDate = dateFormatter.date(from: series.startDate) else {
            print("⚠️ [RECURRING] ERROR: Invalid start date '\(series.startDate)' for series \(series.id)")
            return ([], [])
        }

        // Calculate reasonable maxIterations based on frequency
        let maxIterations = calculateMaxIterations(
            series: series,
            startDate: startDate,
            horizonDate: horizonDate
        )

        var newTransactions: [Transaction] = []
        var newOccurrences: [RecurringOccurrence] = []
        var currentDate = startDate
        var iterationCount = 0

        while currentDate <= horizonDate && iterationCount < maxIterations {
            iterationCount += 1

            let dateString = dateFormatter.string(from: currentDate)
            let occurrenceKey = "\(series.id):\(dateString)"

            // Check if occurrence already exists
            if !existingOccurrenceKeys.contains(occurrenceKey) {
                let amountDouble = NSDecimalNumber(decimal: series.amount).doubleValue
                let transactionDate = dateFormatter.date(from: dateString) ?? Date()
                let createdAt = transactionDate.timeIntervalSince1970

                let transactionId = TransactionIDGenerator.generateID(
                    date: dateString,
                    description: series.description,
                    amount: amountDouble,
                    type: .expense,
                    currency: series.currency,
                    createdAt: createdAt
                )

                // Check if transaction already exists
                if !existingTransactionIds.contains(transactionId) {
                    let occurrenceId = UUID().uuidString

                    let transaction = Transaction(
                        id: transactionId,
                        date: dateString,
                        description: series.description,
                        amount: amountDouble,
                        currency: series.currency,
                        convertedAmount: nil,
                        type: .expense,
                        category: series.category,
                        subcategory: series.subcategory,
                        accountId: series.accountId,
                        targetAccountId: series.targetAccountId,
                        recurringSeriesId: series.id,
                        recurringOccurrenceId: occurrenceId,
                        createdAt: createdAt
                    )

                    let occurrence = RecurringOccurrence(
                        id: occurrenceId,
                        seriesId: series.id,
                        occurrenceDate: dateString,
                        transactionId: transactionId
                    )

                    newTransactions.append(transaction)
                    newOccurrences.append(occurrence)
                    existingOccurrenceKeys.insert(occurrenceKey)
                }
            }

            // Calculate next date based on frequency
            guard let nextDate = calculateNextDate(from: currentDate, frequency: series.frequency) else {
                break
            }

            // Safety check: ensure we're moving forward in time
            if nextDate <= currentDate {
                print("⚠️ [RECURRING] ERROR: nextDate (\(nextDate)) is not greater than currentDate (\(currentDate)) for series \(series.id). Breaking to prevent infinite loop.")
                break
            }

            currentDate = nextDate
        }

        // Log completion
        if iterationCount >= maxIterations {
            print("⚠️ [RECURRING] WARNING: Reached maximum iteration limit (\(maxIterations)) for series '\(series.description)' (ID: \(series.id))")
            print("   Frequency: \(series.frequency), Start: \(series.startDate), Iterations: \(iterationCount)")
            print("   This may indicate a problem with date calculation or an unusually long series.")
        } else if iterationCount > 0 {
            print("✅ [RECURRING] Generated series '\(series.description)' in \(iterationCount) iterations")
        }

        return (newTransactions, newOccurrences)
    }

    // MARK: - Helper Methods

    /// Calculate maximum iterations based on frequency and date range
    private func calculateMaxIterations(
        series: RecurringSeries,
        startDate: Date,
        horizonDate: Date
    ) -> Int {
        let daysBetweenStartAndHorizon = calendar.dateComponents([.day], from: startDate, to: horizonDate).day ?? 0
        guard daysBetweenStartAndHorizon > 0 else { return 1 }

        switch series.frequency {
        case .daily:
            return min(daysBetweenStartAndHorizon + 10, 10000) // Max 10000 for safety
        case .weekly:
            return min((daysBetweenStartAndHorizon / 7) + 10, 2000)
        case .monthly:
            return min((daysBetweenStartAndHorizon / 30) + 10, 500)
        case .yearly:
            return min((daysBetweenStartAndHorizon / 365) + 10, 100)
        }
    }

    /// Calculate next date based on frequency
    private func calculateNextDate(from currentDate: Date, frequency: RecurringFrequency) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: currentDate)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: currentDate)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: currentDate)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: currentDate)
        }
    }

    // MARK: - Future Transaction Cleanup

    /// Delete future transactions and occurrences for a series
    /// Used when regenerating transactions after series modification
    /// - Parameters:
    ///   - seriesId: The series ID
    ///   - transactions: Array of all transactions
    ///   - occurrences: Array of all occurrences
    /// - Returns: Tuple of (filtered transactions, filtered occurrences) with future items removed
    func deleteFutureTransactionsForSeries(
        seriesId: String,
        transactions: [Transaction],
        occurrences: [RecurringOccurrence]
    ) -> (transactions: [Transaction], occurrences: [RecurringOccurrence]) {
        let today = calendar.startOfDay(for: Date())

        // Filter out future transactions for this series
        let filteredTransactions = transactions.filter { transaction in
            guard transaction.recurringSeriesId == seriesId else { return true }
            guard let date = dateFormatter.date(from: transaction.date) else { return true }
            return date <= today
        }

        // Filter out future occurrences for this series
        let filteredOccurrences = occurrences.filter { occurrence in
            guard occurrence.seriesId == seriesId else { return true }
            guard let date = dateFormatter.date(from: occurrence.occurrenceDate) else { return true }
            return date <= today
        }

        return (filteredTransactions, filteredOccurrences)
    }

    // MARK: - Past Transaction Conversion

    /// Convert past recurring transactions to regular transactions
    /// This removes the recurring series ID from transactions that are in the past
    /// - Parameters:
    ///   - transactions: Array of transactions to process
    /// - Returns: Array of transactions with past recurring transactions converted to regular
    func convertPastRecurringToRegular(_ transactions: [Transaction]) -> [Transaction] {
        let today = calendar.startOfDay(for: Date())
        var result: [Transaction] = []

        for transaction in transactions {
            if let _ = transaction.recurringSeriesId,
               let transactionDate = dateFormatter.date(from: transaction.date),
               transactionDate <= today {
                // Convert to regular transaction
                let updatedTransaction = Transaction(
                    id: transaction.id,
                    date: transaction.date,
                    description: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency,
                    convertedAmount: transaction.convertedAmount,
                    type: transaction.type,
                    category: transaction.category,
                    subcategory: transaction.subcategory,
                    accountId: transaction.accountId,
                    targetAccountId: transaction.targetAccountId,
                    recurringSeriesId: nil, // Remove series ID
                    recurringOccurrenceId: nil, // Remove occurrence ID
                    createdAt: transaction.createdAt
                )
                result.append(updatedTransaction)
            } else {
                result.append(transaction)
            }
        }

        return result
    }
}
