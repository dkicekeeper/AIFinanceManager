//
//  TransactionConverterServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for converting validated CSV rows to Transaction objects
/// Handles ID generation, date formatting, and transaction structure creation
@MainActor
protocol TransactionConverterServiceProtocol {
    /// Converts a validated CSV row to a Transaction object
    /// - Parameters:
    ///   - csvRow: Validated CSV row data
    ///   - accountId: Resolved account ID (optional)
    ///   - targetAccountId: Resolved target account ID for transfers (optional)
    ///   - categoryName: Resolved category name
    ///   - categoryId: Resolved category ID
    ///   - subcategoryIds: Array of resolved subcategory IDs
    ///   - rowIndex: Row index for deterministic ID generation
    /// - Returns: Complete Transaction object ready for import
    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryName: String,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction
}
