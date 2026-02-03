//
//  CSVImportCoordinatorFactory.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 5
//

import Foundation

/// Factory for creating CSVImportCoordinator with all dependencies
/// Simplifies initialization in views and tests
@MainActor
extension CSVImportCoordinator {

    /// Creates a fully configured CSVImportCoordinator with default dependencies
    /// - Parameter csvFile: CSV file to configure validator with headers
    /// - Returns: Configured coordinator ready for import
    static func create(for csvFile: CSVFile) -> CSVImportCoordinator {
        let cache = ImportCacheManager(capacity: 1000)

        return CSVImportCoordinator(
            parser: CSVParsingService(),
            validator: CSVValidationService(headers: csvFile.headers),
            mapper: EntityMappingService(cache: cache),
            converter: TransactionConverterService(),
            storage: CSVStorageCoordinator(),
            cache: cache
        )
    }

    /// Creates a coordinator with custom cache capacity
    /// - Parameters:
    ///   - csvFile: CSV file to configure validator
    ///   - cacheCapacity: LRU cache capacity (default: 1000)
    /// - Returns: Configured coordinator
    static func create(
        for csvFile: CSVFile,
        cacheCapacity: Int = 1000
    ) -> CSVImportCoordinator {
        let cache = ImportCacheManager(capacity: cacheCapacity)

        return CSVImportCoordinator(
            parser: CSVParsingService(),
            validator: CSVValidationService(headers: csvFile.headers),
            mapper: EntityMappingService(cache: cache),
            converter: TransactionConverterService(),
            storage: CSVStorageCoordinator(),
            cache: cache
        )
    }
}
