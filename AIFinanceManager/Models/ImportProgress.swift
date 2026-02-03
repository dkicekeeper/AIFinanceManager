//
//  ImportProgress.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation
import Combine

/// Observable progress tracker for CSV import operations
/// Supports cancellation and real-time progress updates
@MainActor
class ImportProgress: ObservableObject {
    // MARK: - Published Properties

    /// Current row being processed (0-based)
    @Published var currentRow: Int = 0

    /// Total number of rows to process
    @Published var totalRows: Int = 0

    /// Flag indicating if import was cancelled by user
    @Published var isCancelled: Bool = false

    // MARK: - Computed Properties

    /// Progress as a fraction from 0.0 to 1.0
    var progress: Double {
        guard totalRows > 0 else { return 0.0 }
        return Double(currentRow) / Double(totalRows)
    }

    /// Progress as a percentage (0-100)
    var percentage: Int {
        Int(progress * 100)
    }

    // MARK: - Methods

    /// Cancels the import operation
    func cancel() {
        isCancelled = true
    }

    /// Resets progress to initial state
    func reset() {
        currentRow = 0
        totalRows = 0
        isCancelled = false
    }
}
