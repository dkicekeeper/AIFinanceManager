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
    
    private let migrationCompletedKey = "coreDataMigrationCompleted_v4"
    
    // MARK: - Public Methods
    
    /// Check if migration is needed
    func isMigrationNeeded() -> Bool {
        let migrationCompleted = UserDefaults.standard.bool(forKey: migrationCompletedKey)
        return !migrationCompleted
    }
    
    /// Perform full migration from UserDefaults to Core Data
    func migrateAllData() async throws {
        guard isMigrationNeeded() else {
            print("✅ [MIGRATION] Data already migrated, skipping")
            return
        }
        
        print("🔄 [MIGRATION] Starting data migration from UserDefaults to Core Data")
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
            
            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.synchronize()
            
            PerformanceProfiler.end("DataMigration.migrateAllData")
            print("✅ [MIGRATION] Data migration completed successfully")
            
        } catch {
            PerformanceProfiler.end("DataMigration.migrateAllData")
            print("❌ [MIGRATION] Migration failed: \(error)")
            throw error
        }
    }
    
    /// Reset migration status (for testing)
    func resetMigrationStatus() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.synchronize()
        print("⚠️ [MIGRATION] Migration status reset")
    }
    
    // MARK: - Clear Core Data
    
    func clearAllCoreData() async throws {
        print("🗑️ [MIGRATION] Clearing all Core Data...")
        
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
                "TransactionSubcategoryLinkEntity"
            ]
            
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                
                try context.execute(deleteRequest)
                print("   ✓ Cleared \(entityName)")
            }
            
            try context.save()
            print("✅ [MIGRATION] All Core Data cleared")
        }
    }
    
    // MARK: - Private Migration Methods
    
    private func migrateAccounts() async throws {
        print("📦 [MIGRATION] Migrating accounts...")
        
        let accounts = userDefaultsRepo.loadAccounts()
        print("📊 [MIGRATION] Found \(accounts.count) accounts to migrate")
        
        guard !accounts.isEmpty else {
            print("⏭️ [MIGRATION] No accounts to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for account in accounts {
                let entity = AccountEntity.from(account, context: context)
                print("   ✓ Migrated account: \(entity.name ?? "Unknown")")
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(accounts.count) accounts to Core Data")
            }
        }
    }
    
    private func migrateTransactions() async throws {
        print("📦 [MIGRATION] Migrating transactions...")
        
        let transactions = userDefaultsRepo.loadTransactions()
        print("📊 [MIGRATION] Found \(transactions.count) transactions to migrate")
        
        guard !transactions.isEmpty else {
            print("⏭️ [MIGRATION] No transactions to migrate")
            return
        }
        
        // Migrate in batches to avoid memory issues
        let batchSize = 500
        let batches = stride(from: 0, to: transactions.count, by: batchSize).map {
            Array(transactions[$0..<min($0 + batchSize, transactions.count)])
        }
        
        print("📊 [MIGRATION] Migrating in \(batches.count) batches")
        
        for (index, batch) in batches.enumerated() {
            try await migrateBatch(batch, batchIndex: index + 1, totalBatches: batches.count)
        }
        
        print("✅ [MIGRATION] All transactions migrated successfully")
    }
    
    private func migrateBatch(_ transactions: [Transaction], batchIndex: Int, totalBatches: Int) async throws {
        print("   📦 [MIGRATION] Batch \(batchIndex)/\(totalBatches): \(transactions.count) transactions")
        
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
                print("   ✅ [MIGRATION] Batch \(batchIndex) saved")
            }
        }
    }
    
    private func migrateCategorySubcategoryLinks() async throws {
        print("📦 [MIGRATION] Migrating category-subcategory links...")
        
        let links = userDefaultsRepo.loadCategorySubcategoryLinks()
        print("📊 [MIGRATION] Found \(links.count) category-subcategory links to migrate")
        
        guard !links.isEmpty else {
            print("⏭️ [MIGRATION] No category-subcategory links to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for link in links {
                _ = CategorySubcategoryLinkEntity.from(link, context: context)
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(links.count) category-subcategory links to Core Data")
            }
        }
    }
    
    private func migrateTransactionSubcategoryLinks() async throws {
        print("📦 [MIGRATION] Migrating transaction-subcategory links...")
        
        let links = userDefaultsRepo.loadTransactionSubcategoryLinks()
        print("📊 [MIGRATION] Found \(links.count) transaction-subcategory links to migrate")
        
        guard !links.isEmpty else {
            print("⏭️ [MIGRATION] No transaction-subcategory links to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for link in links {
                _ = TransactionSubcategoryLinkEntity.from(link, context: context)
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(links.count) transaction-subcategory links to Core Data")
            }
        }
    }
    
    private func migrateSubcategories() async throws {
        print("📦 [MIGRATION] Migrating subcategories...")
        
        let subcategories = userDefaultsRepo.loadSubcategories()
        print("📊 [MIGRATION] Found \(subcategories.count) subcategories to migrate")
        
        guard !subcategories.isEmpty else {
            print("⏭️ [MIGRATION] No subcategories to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for subcategory in subcategories {
                _ = SubcategoryEntity.from(subcategory, context: context)
                print("   ✓ Migrated subcategory: \(subcategory.name)")
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(subcategories.count) subcategories to Core Data")
            }
        }
    }
    
    private func migrateCategoryRules() async throws {
        print("📦 [MIGRATION] Migrating category rules...")
        
        let rules = userDefaultsRepo.loadCategoryRules()
        print("📊 [MIGRATION] Found \(rules.count) rules to migrate")
        
        guard !rules.isEmpty else {
            print("⏭️ [MIGRATION] No category rules to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for rule in rules {
                _ = CategoryRuleEntity.from(rule, context: context)
                print("   ✓ Migrated rule: \(rule.description) → \(rule.category)")
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(rules.count) category rules to Core Data")
            }
        }
    }
    
    private func migrateCustomCategories() async throws {
        print("📦 [MIGRATION] Migrating custom categories...")
        
        let categories = userDefaultsRepo.loadCategories()
        print("📊 [MIGRATION] Found \(categories.count) categories to migrate")
        
        guard !categories.isEmpty else {
            print("⏭️ [MIGRATION] No categories to migrate")
            return
        }
        
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            for category in categories {
                _ = CustomCategoryEntity.from(category, context: context)
                print("   ✓ Migrated category: \(category.name)")
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(categories.count) categories to Core Data")
            }
        }
    }
    
    private func migrateRecurringSeries() async throws {
        print("📦 [MIGRATION] Migrating recurring series...")
        
        let series = userDefaultsRepo.loadRecurringSeries()
        print("📊 [MIGRATION] Found \(series.count) recurring series to migrate")
        
        guard !series.isEmpty else {
            print("⏭️ [MIGRATION] No recurring series to migrate")
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
                
                print("   ✓ Migrated recurring series: \(item.description)")
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ [MIGRATION] Saved \(series.count) recurring series to Core Data")
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
