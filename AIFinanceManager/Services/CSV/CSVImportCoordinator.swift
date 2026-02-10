//
//  CSVImportCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 2
//

import Foundation

/// Main coordinator for CSV import operations
/// Orchestrates the entire import flow with dependency injection and progress tracking
/// Replaced the deprecated monolithic CSVImportService (deleted 2026-02-04)
@MainActor
class CSVImportCoordinator: CSVImportCoordinatorProtocol {

    // MARK: - Dependencies

    private let parser: CSVParsingServiceProtocol
    private let validator: CSVValidationServiceProtocol
    private let mapper: EntityMappingServiceProtocol
    private let converter: TransactionConverterServiceProtocol
    private let storage: CSVStorageCoordinatorProtocol
    private let cache: ImportCacheManager

    // MARK: - Initialization

    init(
        parser: CSVParsingServiceProtocol,
        validator: CSVValidationServiceProtocol,
        mapper: EntityMappingServiceProtocol,
        converter: TransactionConverterServiceProtocol,
        storage: CSVStorageCoordinatorProtocol,
        cache: ImportCacheManager
    ) {
        self.parser = parser
        self.validator = validator
        self.mapper = mapper
        self.converter = converter
        self.storage = storage
        self.cache = cache
    }

    // MARK: - CSVImportCoordinatorProtocol

    func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel?,
        progress: ImportProgress
    ) async -> ImportStatistics {

        let startTime = Date()

        // Initialize statistics builder
        let stats = ImportStatisticsBuilder()
        stats.totalRows = csvFile.rowCount

        // Build fingerprint set for duplicate detection
        let existingFingerprints = Set(
            transactionsViewModel.allTransactions.map { TransactionFingerprint(from: $0) }
        )

        // Begin import mode in TransactionStore (defers persistence)
        if let transactionStore = transactionsViewModel.transactionStore {
            await transactionStore.beginImport()
        }

        // Begin batch mode
        transactionsViewModel.beginBatch()

        // Process rows in batches
        var transactionsBatch: [Transaction] = []
        var subcategoryLinksBatch: [String: [String]] = [:]
        transactionsBatch.reserveCapacity(500)

        for (rowIndex, row) in csvFile.rows.enumerated() {

            // Check cancellation
            if progress.isCancelled {
                break
            }

            // Update progress
            progress.currentRow = rowIndex + 1

            // Validate row
            let validationResult = validator.validateRow(
                row,
                at: rowIndex,
                mapping: columnMapping
            )

            guard case .success(let csvRow) = validationResult else {
                if case .failure(let error) = validationResult {
                    stats.addError(error)
                }
                stats.incrementSkipped()
                continue
            }

            // Resolve account
            let accountResult = await mapper.resolveAccount(
                name: csvRow.effectiveAccountValue,
                currency: csvRow.currency,
                mapping: entityMapping,
                accountsViewModel: accountsViewModel
            )

            let accountId: String?
            switch accountResult {
            case .existing(let id), .created(let id):
                accountId = id
                if case .created = accountResult {
                    stats.incrementCreatedAccounts()
                }
            case .skipped:
                accountId = nil
            }

            // Resolve target account (for transfers)
            var targetAccountId: String? = nil
            if csvRow.type != .income,
               let targetAccountValue = csvRow.rawTargetAccountValue,
               !targetAccountValue.isEmpty {

                let targetResult = await mapper.resolveAccount(
                    name: targetAccountValue,
                    currency: csvRow.targetCurrency ?? csvRow.currency,
                    mapping: entityMapping,
                    accountsViewModel: accountsViewModel
                )

                switch targetResult {
                case .existing(let id), .created(let id):
                    targetAccountId = id
                    if case .created = targetResult {
                        stats.incrementCreatedAccounts()
                    }
                case .skipped:
                    break
                }
            }

            // Resolve category
            let categoryName = resolveCategoryName(for: csvRow)

            let categoryResult = await mapper.resolveCategory(
                name: categoryName,
                type: csvRow.type,
                mapping: entityMapping,
                categoriesViewModel: categoriesViewModel
            )

            let categoryId: String
            let finalCategoryName: String
            switch categoryResult {
            case .existing(let id, let name):
                categoryId = id
                finalCategoryName = name
            case .created(let id, let name):
                categoryId = id
                finalCategoryName = name
                stats.incrementCreatedCategories()
            }

            // Resolve subcategories
            var subcategoryIds: [String] = []
            if !csvRow.subcategoryNames.isEmpty {
                let subcategoryResults = await mapper.resolveSubcategories(
                    names: csvRow.subcategoryNames,
                    categoryId: categoryId,
                    categoriesViewModel: categoriesViewModel
                )

                for result in subcategoryResults {
                    switch result {
                    case .existing(let id):
                        subcategoryIds.append(id)
                    case .created(let id):
                        subcategoryIds.append(id)
                        stats.incrementCreatedSubcategories()
                    }
                }
            }

            // Convert to transaction
            let transaction = converter.convertRow(
                csvRow,
                accountId: accountId,
                targetAccountId: targetAccountId,
                categoryName: finalCategoryName,
                categoryId: categoryId,
                subcategoryIds: subcategoryIds,
                rowIndex: rowIndex
            )

            // Check duplicates
            let fingerprint = TransactionFingerprint(from: transaction)
            if existingFingerprints.contains(fingerprint) {
                stats.incrementDuplicates()
                stats.incrementSkipped()
                continue
            }

            // Add to batch
            transactionsBatch.append(transaction)
            if !subcategoryIds.isEmpty {
                subcategoryLinksBatch[transaction.id] = subcategoryIds
            }

            stats.incrementImported()

            // Process batch if full or last row
            if transactionsBatch.count >= 500 || rowIndex == csvFile.rowCount - 1 {
                await storage.saveBatch(
                    transactionsBatch,
                    subcategoryLinks: subcategoryLinksBatch,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel
                )

                transactionsBatch.removeAll(keepingCapacity: true)
                subcategoryLinksBatch.removeAll(keepingCapacity: true)
            }
        }

        // Finalize import
        await storage.finalizeImport(
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel
        )

        // Clear cache
        cache.clear()

        // Build final statistics
        let duration = Date().timeIntervalSince(startTime)
        return stats.build(duration: duration)
    }

    // MARK: - Private Helpers

    private func resolveCategoryName(for csvRow: CSVRow) -> String {
        if csvRow.type == .internalTransfer {
            return String(localized: "transactionForm.transfer")
        } else if csvRow.effectiveCategoryValue.isEmpty {
            return String(localized: "category.other")
        } else {
            return csvRow.effectiveCategoryValue
        }
    }
}

// MARK: - Statistics Builder

/// Helper class for building import statistics
private class ImportStatisticsBuilder {
    var totalRows: Int = 0
    var importedCount: Int = 0
    var skippedCount: Int = 0
    var duplicatesSkipped: Int = 0
    var createdAccounts: Int = 0
    var createdCategories: Int = 0
    var createdSubcategories: Int = 0
    var errors: [CSVValidationError] = []

    func incrementImported() { importedCount += 1 }
    func incrementSkipped() { skippedCount += 1 }
    func incrementDuplicates() { duplicatesSkipped += 1 }
    func incrementCreatedAccounts() { createdAccounts += 1 }
    func incrementCreatedCategories() { createdCategories += 1 }
    func incrementCreatedSubcategories() { createdSubcategories += 1 }
    func addError(_ error: CSVValidationError) { errors.append(error) }

    func build(duration: TimeInterval) -> ImportStatistics {
        let rowsPerSecond = totalRows > 0 ? Double(totalRows) / duration : 0.0

        return ImportStatistics(
            totalRows: totalRows,
            importedCount: importedCount,
            skippedCount: skippedCount,
            duplicatesSkipped: duplicatesSkipped,
            createdAccounts: createdAccounts,
            createdCategories: createdCategories,
            createdSubcategories: createdSubcategories,
            duration: duration,
            rowsPerSecond: rowsPerSecond,
            errors: errors
        )
    }
}
