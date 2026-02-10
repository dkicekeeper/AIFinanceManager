//
//  ImportFlowCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 2
//

import Foundation
import SwiftUI
import Combine

/// Coordinator for CSV import flow state management
/// Manages multi-step import process: file selection → preview → mapping → import → results
@MainActor
final class ImportFlowCoordinator: ObservableObject {
    // MARK: - Published State

    @Published var currentStep: ImportStep = .idle
    @Published var csvFile: CSVFile?
    @Published var columnMapping: CSVColumnMapping?
    @Published var entityMapping: EntityMapping = EntityMapping()
    @Published var importProgress: ImportProgress?
    @Published var importResult: ImportStatistics?
    @Published var errorMessage: String?

    // MARK: - Import Steps

    enum ImportStep: Equatable {
        case idle
        case selectingFile
        case preview
        case columnMapping
        case entityMapping
        case importing
        case result
        case error(String)
    }

    // MARK: - Dependencies

    private var importCoordinator: CSVImportCoordinatorProtocol?
    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var accountsViewModel: AccountsViewModel?

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel?,
        categoriesViewModel: CategoriesViewModel?,
        accountsViewModel: AccountsViewModel?
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - Flow Control

    /// Start import flow with file URL
    func startImport(from url: URL) async {
        currentStep = .selectingFile

        do {
            // Parse CSV file
            let file = try CSVImporter.parseCSV(from: url)
            csvFile = file

            // ✨ Phase 11: Create CSVImportCoordinator with TransactionStore
            if let transactionStore = transactionsViewModel?.transactionStore {
                importCoordinator = CSVImportCoordinator.create(
                    for: file,
                    transactionStore: transactionStore
                )
            } else {
                throw CSVImportError.missingDependency("TransactionStore not available")
            }

            currentStep = .preview

            #if DEBUG
            print("📥 [ImportFlow] File parsed: \(file.rowCount) rows")
            #endif
        } catch {
            handleError(error)
        }
    }

    /// Continue to column mapping
    func continueToColumnMapping() {
        #if DEBUG
        print("🔄 [ImportFlow] Continue button tapped")
        print("   📄 CSV file exists: \(csvFile != nil)")
        print("   🎯 Current step before: \(currentStep)")
        #endif

        guard csvFile != nil else {
            #if DEBUG
            print("   ❌ No CSV file loaded")
            #endif
            currentStep = .error("No CSV file loaded")
            return
        }

        currentStep = .columnMapping

        #if DEBUG
        print("   ✅ Transitioned to: \(currentStep)")
        #endif
    }

    /// Continue to entity mapping
    func continueToEntityMapping(with mapping: CSVColumnMapping) {
        columnMapping = mapping
        currentStep = .entityMapping
    }

    /// Start import with mappings
    func performImport() async {
        guard let csvFile = csvFile,
              let columnMapping = columnMapping,
              let importCoordinator = importCoordinator,
              let transactionsViewModel = transactionsViewModel,
              let categoriesViewModel = categoriesViewModel else {
            currentStep = .error("Missing required data for import")
            return
        }

        currentStep = .importing

        // Create progress tracker
        let progress = ImportProgress()
        progress.totalRows = csvFile.rowCount
        importProgress = progress

        #if DEBUG
        print("📥 [ImportFlow] Starting import: \(csvFile.rowCount) rows")
        #endif

        // Perform import
        let result = await importCoordinator.importTransactions(
            csvFile: csvFile,
            columnMapping: columnMapping,
            entityMapping: entityMapping,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            progress: progress
        )

        importResult = result
        currentStep = .result

        #if DEBUG
        print("✅ [ImportFlow] Import completed")
        print("   📊 Imported: \(result.importedCount)")
        print("   ⏭️ Skipped: \(result.skippedCount)")
        print("   🏦 Created accounts: \(result.createdAccounts)")
        print("   🏷️ Created categories: \(result.createdCategories)")
        #endif

        // Trigger haptic feedback
        if result.errors.isEmpty {
            HapticManager.success()
        } else {
            HapticManager.warning()
        }
    }

    /// Cancel import flow
    func cancel() {
        if let progress = importProgress {
            progress.cancel()
        }
        reset()
    }

    /// Reset flow to initial state
    func reset() {
        currentStep = .idle
        csvFile = nil
        columnMapping = nil
        entityMapping = EntityMapping()
        importProgress = nil
        importResult = nil
        errorMessage = nil
        importCoordinator = nil
    }

    // MARK: - Private Helpers

    private func handleError(_ error: Error) {
        let message = error.localizedDescription
        errorMessage = message
        currentStep = .error(message)

        #if DEBUG
        print("❌ [ImportFlow] Error: \(message)")
        #endif
    }
}
