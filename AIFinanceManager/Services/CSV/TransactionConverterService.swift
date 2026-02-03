//
//  TransactionConverterService.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 2
//

import Foundation

/// Service for converting validated CSV rows to Transaction objects
/// Handles ID generation, date formatting, and transaction structure
@MainActor
class TransactionConverterService: TransactionConverterServiceProtocol {

    // MARK: - TransactionConverterServiceProtocol

    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryName: String,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction {

        // Format date
        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: csvRow.date)

        // Generate deterministic createdAt (date + row offset for sorting)
        let createdAt = csvRow.date.timeIntervalSince1970 + Double(rowIndex) * 0.001

        // Generate transaction ID
        let descriptionForID = csvRow.note?.isEmpty == false
            ? csvRow.note!
            : categoryName

        let transactionId = TransactionIDGenerator.generateID(
            date: dateString,
            description: descriptionForID,
            amount: csvRow.amount,
            type: csvRow.type,
            currency: csvRow.currency,
            createdAt: createdAt
        )

        // Get first subcategory name for backward compatibility
        let subcategoryName = csvRow.subcategoryNames.first

        // Create transaction
        return Transaction(
            id: transactionId,
            date: dateString,
            description: csvRow.note ?? "",
            amount: csvRow.amount,
            currency: csvRow.currency,
            convertedAmount: nil,
            type: csvRow.type,
            category: categoryName,
            subcategory: subcategoryName,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: nil, // Will be resolved by coordinator
            targetAccountName: nil, // Will be resolved by coordinator
            targetCurrency: csvRow.targetCurrency,
            targetAmount: csvRow.targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )
    }
}
