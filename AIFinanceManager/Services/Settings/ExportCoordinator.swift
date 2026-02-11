//
//  ExportCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation
import Observation

/// Coordinator for data export operations
/// Handles CSV export with progress tracking and async operations
/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
final class ExportCoordinator: ExportCoordinatorProtocol {
    // MARK: - Observable State

    private(set) var exportProgress: Double = 0

    // MARK: - Dependencies (weak to prevent retain cycles)

    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var accountsViewModel: AccountsViewModel?

    init(
        transactionsViewModel: TransactionsViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - ExportCoordinatorProtocol

    func exportAllData() async throws -> URL {
        #if DEBUG
        print("📤 [ExportCoordinator] Starting data export")
        #endif

        guard let transactionsViewModel = transactionsViewModel else {
            throw ExportError.exportFailed(underlying: NSError(
                domain: "ExportCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "TransactionsViewModel not available"]
            ))
        }

        guard let accountsViewModel = accountsViewModel else {
            throw ExportError.exportFailed(underlying: NSError(
                domain: "ExportCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AccountsViewModel not available"]
            ))
        }

        let transactions = transactionsViewModel.allTransactions
        let accounts = accountsViewModel.accounts

        // Check if there's data to export
        guard !transactions.isEmpty else {
            throw ExportError.noDataToExport
        }

        // Reset progress
        await MainActor.run {
            exportProgress = 0
        }

        // Perform export in background
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: ExportError.exportFailed(underlying: NSError(
                        domain: "ExportCoordinator",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "ExportCoordinator deallocated"]
                    )))
                    return
                }

                do {
                    // Update progress: Starting
                    await self.updateProgress(0.1)

                    // Generate CSV string
                    let csvString = CSVExporter.exportTransactions(
                        transactions,
                        accounts: accounts
                    )

                    // Update progress: CSV generated
                    await self.updateProgress(0.7)

                    // Generate filename
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
                    let dateString = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let fileName = "transactions_export_\(dateString).csv"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                    // Update progress: Writing file
                    await self.updateProgress(0.9)

                    // Write to file
                    try csvString.write(to: tempURL, atomically: true, encoding: .utf8)

                    // Update progress: Complete
                    await self.updateProgress(1.0)

                    #if DEBUG
                    await MainActor.run {
                        print("✅ [ExportCoordinator] Export completed: \(fileName)")
                        print("   📊 Exported \(transactions.count) transactions")
                    }
                    #endif

                    continuation.resume(returning: tempURL)
                } catch {
                    #if DEBUG
                    await MainActor.run {
                        print("❌ [ExportCoordinator] Export failed: \(error)")
                    }
                    #endif

                    if let urlError = error as? URLError {
                        continuation.resume(throwing: ExportError.fileWriteFailed(underlying: urlError))
                    } else if let exportError = error as? ExportError {
                        continuation.resume(throwing: exportError)
                    } else {
                        continuation.resume(throwing: ExportError.exportFailed(underlying: error))
                    }
                }
            }
        }
    }

    // MARK: - Dependency Injection

    func setDependencies(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - Private Helpers

    /// Update export progress (already on MainActor via class isolation)
    private func updateProgress(_ value: Double) {
        exportProgress = value
    }
}
