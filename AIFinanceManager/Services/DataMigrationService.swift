//
//  DataMigrationService.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Service for migrating data from UserDefaults to Core Data

import Foundation
import CoreData

/// Service responsible for migrating data from UserDefaults to Core Data
@MainActor
class DataMigrationService {
    
    // MARK: - Properties
    
    private let userDefaultsRepo = UserDefaultsRepository()
    private let coreDataRepo = CoreDataRepository()
    private let stack = CoreDataStack.shared
    
    // MARK: - Migration Status Key

    private let migrationCompletedKey = "coreDataMigrationCompleted_v5"
    
    // MARK: - Public Methods
    
    /// Check if migration is needed
    func isMigrationNeeded() -> Bool {
        let migrationCompleted = UserDefaults.standard.bool(forKey: migrationCompletedKey)
        return !migrationCompleted
    }
    
    /// Perform full migration from UserDefaults to Core Data
    func migrateAllData() async throws {
        guard isMigrationNeeded() else {
            return
        }

        PerformanceProfiler.start("DataMigration.migrateAllData")

        do {
            // Step 1: Migrate Accounts first (since Transactions reference them)
            try await migrateAccounts()

            // Step 2: Migrate Transactions
            try await migrateTransactions()

            // Step 3: Migrate Recurring Series
            try await migrateRecurringSeries()

            // Step 4: Migrate Custom Categories
            try await migrateCustomCategories()

            // Step 5: Migrate Category Rules
            try await migrateCategoryRules()

            // Step 6: Migrate Subcategories
            try await migrateSubcategories()

            // Step 7: Migrate Category-Subcategory Links
            try await migrateCategorySubcategoryLinks()

            // Step 8: Migrate Transaction-Subcategory Links
            try await migrateTransactionSubcategoryLinks()

            // Step 9: Migrate Recurring Occurrences
            try await migrateRecurringOccurrences()

            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.synchronize()

            PerformanceProfiler.end("DataMigration.migrateAllData")

        } catch {
            PerformanceProfiler.end("DataMigration.migrateAllData")
            throw error
        }
    }
    
    /// Reset migration status (for testing)
    func resetMigrationStatus() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Clear Core Data
    
    func clearAllCoreData() async throws {
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            let entityNames = [
                "TransactionEntity",
                "AccountEntity",
                "RecurringSeriesEntity",
                "CustomCategoryEntity",
                "CategoryRuleEntity",
                "SubcategoryEntity",
                "CategorySubcategoryLinkEntity",
                "TransactionSubcategoryLinkEntity",
                "RecurringOccurrenceEntity"
            ]
            
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                
                try context.execute(deleteRequest)
            }
            
            try context.save()
        }
    }
    
    // MARK: - Private Migration Methods
    
    private func migrateAccounts() async throws {
        
        let accounts = userDefaultsRepo.loadAccounts()
        
        guard !accounts.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for account in accounts {
                _ = AccountEntity.from(account, context: context)
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateTransactions() async throws {
        
        let transactions = userDefaultsRepo.loadTransactions()
        
        guard !transactions.isEmpty else {
            return
        }
        
        // Migrate in batches to avoid memory issues
        let batchSize = 500
        let batches = stride(from: 0, to: transactions.count, by: batchSize).map {
            Array(transactions[$0..<min($0 + batchSize, transactions.count)])
        }
        
        
        for (index, batch) in batches.enumerated() {
            try await migrateBatch(batch, batchIndex: index + 1, totalBatches: batches.count)
        }
        
    }
    
    private func migrateBatch(_ transactions: [Transaction], batchIndex: Int, totalBatches: Int) async throws {
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for transaction in transactions {
                let entity = TransactionEntity.from(transaction, context: context)
                
                // Set account relationship if exists
                if let accountId = transaction.accountId {
                    entity.account = self.fetchAccount(id: accountId, context: context)
                }
                
                // Set target account relationship if exists
                if let targetAccountId = transaction.targetAccountId {
                    entity.targetAccount = self.fetchAccount(id: targetAccountId, context: context)
                }
                
                // Set recurring series relationship if exists
                if let seriesId = transaction.recurringSeriesId {
                    entity.recurringSeries = self.fetchRecurringSeries(id: seriesId, context: context)
                }
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateCategorySubcategoryLinks() async throws {
        
        let links = userDefaultsRepo.loadCategorySubcategoryLinks()
        
        guard !links.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for link in links {
                _ = CategorySubcategoryLinkEntity.from(link, context: context)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateTransactionSubcategoryLinks() async throws {
        
        let links = userDefaultsRepo.loadTransactionSubcategoryLinks()
        
        guard !links.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for link in links {
                _ = TransactionSubcategoryLinkEntity.from(link, context: context)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateSubcategories() async throws {
        
        let subcategories = userDefaultsRepo.loadSubcategories()
        
        guard !subcategories.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for subcategory in subcategories {
                _ = SubcategoryEntity.from(subcategory, context: context)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateCategoryRules() async throws {
        
        let rules = userDefaultsRepo.loadCategoryRules()
        
        guard !rules.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for rule in rules {
                _ = CategoryRuleEntity.from(rule, context: context)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateCustomCategories() async throws {
        
        let categories = userDefaultsRepo.loadCategories()
        
        guard !categories.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for category in categories {
                _ = CustomCategoryEntity.from(category, context: context)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateRecurringSeries() async throws {
        
        let series = userDefaultsRepo.loadRecurringSeries()
        
        guard !series.isEmpty else {
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for item in series {
                let entity = RecurringSeriesEntity.from(item, context: context)
                
                // Set account relationship if exists
                if let accountId = item.accountId {
                    entity.account = self.fetchAccount(id: accountId, context: context)
                }
                
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    private func migrateRecurringOccurrences() async throws {

        let occurrences = userDefaultsRepo.loadRecurringOccurrences()

        guard !occurrences.isEmpty else {
            return
        }

        let context = stack.newBackgroundContext()

        try await context.perform {
            for occurrence in occurrences {
                let entity = RecurringOccurrenceEntity.from(occurrence, context: context)

                // Set series relationship if exists
                if !occurrence.seriesId.isEmpty {
                    entity.series = self.fetchRecurringSeries(id: occurrence.seriesId, context: context)
                }

            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - Helper Methods

    private nonisolated func fetchAccount(id: String, context: NSManagedObjectContext) -> AccountEntity? {
        let request = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    private nonisolated func fetchRecurringSeries(id: String, context: NSManagedObjectContext) -> RecurringSeriesEntity? {
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
}

// MARK: - Migration Error

enum MigrationError: Error {
    case alreadyMigrated
    case migrationFailed(Error)
    case dataCorrupted
    
    var localizedDescription: String {
        switch self {
        case .alreadyMigrated:
            return "Data has already been migrated"
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .dataCorrupted:
            return "Source data is corrupted"
        }
    }
}
