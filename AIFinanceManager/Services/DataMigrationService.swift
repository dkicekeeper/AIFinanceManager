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
    
    private let migrationCompletedKey = "coreDataMigrationCompleted_v1"
    
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
            // TODO: Implement when RecurringSeriesEntity is ready
            
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
