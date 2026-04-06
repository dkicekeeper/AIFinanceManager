//
//  CSVImportCoordinatorFactory.swift
//  Tenra
//
//  Factory for creating CSVImportCoordinator with default dependencies.
//

import Foundation

/// Factory for creating CSVImportCoordinator with all dependencies
/// Simplified to work directly with TransactionStore
@MainActor
extension CSVImportCoordinator {

    /// Creates a fully configured CSVImportCoordinator with default dependencies
    /// - Parameters:
    ///   - csvFile: CSV file to configure validator with headers
    ///   - transactionStore: TransactionStore instance for direct data manipulation
    /// - Returns: Configured coordinator ready for import
    static func create(
        for csvFile: CSVFile,
        transactionStore: TransactionStore
    ) -> CSVImportCoordinator {
        let cache = ImportCacheManager(capacity: 1000)

        return CSVImportCoordinator(
            parser: CSVParsingService(),
            validator: CSVValidationService(headers: csvFile.headers),
            mapper: EntityMappingService(cache: cache, transactionStore: transactionStore),
            cache: cache
        )
    }

    /// Creates a coordinator with custom cache capacity
    static func create(
        for csvFile: CSVFile,
        transactionStore: TransactionStore,
        cacheCapacity: Int = 1000
    ) -> CSVImportCoordinator {
        let cache = ImportCacheManager(capacity: cacheCapacity)

        return CSVImportCoordinator(
            parser: CSVParsingService(),
            validator: CSVValidationService(headers: csvFile.headers),
            mapper: EntityMappingService(cache: cache, transactionStore: transactionStore),
            cache: cache
        )
    }
}
