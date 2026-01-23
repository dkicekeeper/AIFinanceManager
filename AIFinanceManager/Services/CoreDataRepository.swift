//
//  CoreDataRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Core Data implementation of DataRepositoryProtocol

import Foundation
import CoreData

/// Core Data implementation of DataRepositoryProtocol
/// Handles all data persistence operations using Core Data
final class CoreDataRepository: DataRepositoryProtocol {
    
    // MARK: - Properties
    
    private let stack = CoreDataStack.shared
    private let userDefaultsRepository = UserDefaultsRepository()
    
    // MARK: - Initialization
    
    init() {
        print("🗄️ [CORE_DATA_REPO] Initializing CoreDataRepository")
    }
    
    // MARK: - Transactions
    
    func loadTransactions() -> [Transaction] {
        print("📂 [CORE_DATA_REPO] Loading transactions from Core Data")
        PerformanceProfiler.start("CoreDataRepository.loadTransactions")
        
        let context = stack.viewContext
        let request = TransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            let transactions = entities.map { $0.toTransaction() }
            
            PerformanceProfiler.end("CoreDataRepository.loadTransactions")
            print("✅ [CORE_DATA_REPO] Loaded \(transactions.count) transactions")
            
            return transactions
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading transactions: \(error)")
            PerformanceProfiler.end("CoreDataRepository.loadTransactions")
            
            // Fallback to UserDefaults if Core Data fails
            print("⚠️ [CORE_DATA_REPO] Falling back to UserDefaults")
            return userDefaultsRepository.loadTransactions()
        }
    }
    
    func saveTransactions(_ transactions: [Transaction]) {
        print("💾 [CORE_DATA_REPO] Saving \(transactions.count) transactions to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveTransactions")
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // First, fetch all existing transactions to update or delete
                    let fetchRequest = TransactionEntity.fetchRequest()
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    // Track which IDs we're keeping
                    var keptIds = Set<String>()
                    
                    // Update or create transactions
                    for transaction in transactions {
                        keptIds.insert(transaction.id)
                        
                        if let existing = existingDict[transaction.id] {
                            // Update existing
                            existing.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
                            existing.descriptionText = transaction.description
                            existing.amount = transaction.amount
                            existing.currency = transaction.currency
                            existing.convertedAmount = transaction.convertedAmount ?? 0
                            existing.type = transaction.type.rawValue
                            existing.category = transaction.category
                            existing.subcategory = transaction.subcategory
                            existing.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
                            
                            // Update relationships if needed
                            if let accountId = transaction.accountId {
                                existing.account = self.fetchAccountSync(id: accountId, context: context)
                            }
                            if let targetAccountId = transaction.targetAccountId {
                                existing.targetAccount = self.fetchAccountSync(id: targetAccountId, context: context)
                            }
                            if let seriesId = transaction.recurringSeriesId {
                                existing.recurringSeries = self.fetchRecurringSeriesSync(id: seriesId, context: context)
                            }
                        } else {
                            // Create new
                            let entity = TransactionEntity.from(transaction, context: context)
                            
                            // Set relationships if needed
                            if let accountId = transaction.accountId {
                                entity.account = self.fetchAccountSync(id: accountId, context: context)
                            }
                            if let targetAccountId = transaction.targetAccountId {
                                entity.targetAccount = self.fetchAccountSync(id: targetAccountId, context: context)
                            }
                            if let seriesId = transaction.recurringSeriesId {
                                entity.recurringSeries = self.fetchRecurringSeriesSync(id: seriesId, context: context)
                            }
                        }
                    }
                    
                    // Delete transactions that no longer exist
                    for entity in existingEntities {
                        if let id = entity.id, !keptIds.contains(id) {
                            context.delete(entity)
                        }
                    }
                    
                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("❌ [CORE_DATA_REPO] Error saving transactions: \(error)")
                }
            }
            
            PerformanceProfiler.end("CoreDataRepository.saveTransactions")
            print("✅ [CORE_DATA_REPO] Transactions saved successfully")
        }
    }
    
    // MARK: - Accounts
    
    func loadAccounts() -> [Account] {
        print("📂 [CORE_DATA_REPO] Loading accounts from Core Data")
        PerformanceProfiler.start("CoreDataRepository.loadAccounts")
        
        let context = stack.viewContext
        let request = AccountEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let accounts = entities.map { $0.toAccount() }
            
            PerformanceProfiler.end("CoreDataRepository.loadAccounts")
            print("✅ [CORE_DATA_REPO] Loaded \(accounts.count) accounts")
            
            return accounts
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading accounts: \(error)")
            PerformanceProfiler.end("CoreDataRepository.loadAccounts")
            
            // Fallback to UserDefaults if Core Data fails
            print("⚠️ [CORE_DATA_REPO] Falling back to UserDefaults")
            return userDefaultsRepository.loadAccounts()
        }
    }
    
    func saveAccounts(_ accounts: [Account]) {
        print("💾 [CORE_DATA_REPO] Saving \(accounts.count) accounts to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveAccounts")
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing accounts
                    let fetchRequest = AccountEntity.fetchRequest()
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create accounts
                    for account in accounts {
                        keptIds.insert(account.id)
                        
                        if let existing = existingDict[account.id] {
                            // Update existing
                            existing.name = account.name
                            existing.balance = account.balance
                            existing.currency = account.currency
                            existing.logo = account.bankLogo.rawValue
                            existing.isDeposit = account.isDeposit
                            existing.bankName = account.depositInfo?.bankName
                        } else {
                            // Create new
                            _ = AccountEntity.from(account, context: context)
                        }
                    }
                    
                    // Delete accounts that no longer exist
                    for entity in existingEntities {
                        if let id = entity.id, !keptIds.contains(id) {
                            context.delete(entity)
                        }
                    }
                    
                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("❌ [CORE_DATA_REPO] Error saving accounts: \(error)")
                }
            }
            
            PerformanceProfiler.end("CoreDataRepository.saveAccounts")
            print("✅ [CORE_DATA_REPO] Accounts saved successfully")
        }
    }
    
    // MARK: - Recurring Series
    
    func loadRecurringSeries() -> [RecurringSeries] {
        // For now, use UserDefaults fallback
        // TODO: Implement Core Data storage for RecurringSeries
        return userDefaultsRepository.loadRecurringSeries()
    }
    
    func saveRecurringSeries(_ series: [RecurringSeries]) {
        // For now, use UserDefaults fallback
        // TODO: Implement Core Data storage for RecurringSeries
        userDefaultsRepository.saveRecurringSeries(series)
    }
    
    // MARK: - Categories (Fallback to UserDefaults)
    
    func loadCategories() -> [CustomCategory] {
        return userDefaultsRepository.loadCategories()
    }
    
    func saveCategories(_ categories: [CustomCategory]) {
        userDefaultsRepository.saveCategories(categories)
    }
    
    // MARK: - Category Rules (Fallback to UserDefaults)
    
    func loadCategoryRules() -> [CategoryRule] {
        return userDefaultsRepository.loadCategoryRules()
    }
    
    func saveCategoryRules(_ rules: [CategoryRule]) {
        userDefaultsRepository.saveCategoryRules(rules)
    }
    
    // MARK: - Recurring Occurrences (Fallback to UserDefaults)
    
    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        return userDefaultsRepository.loadRecurringOccurrences()
    }
    
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {
        userDefaultsRepository.saveRecurringOccurrences(occurrences)
    }
    
    // MARK: - Subcategories (Fallback to UserDefaults)
    
    func loadSubcategories() -> [Subcategory] {
        return userDefaultsRepository.loadSubcategories()
    }
    
    func saveSubcategories(_ subcategories: [Subcategory]) {
        userDefaultsRepository.saveSubcategories(subcategories)
    }
    
    // MARK: - Category-Subcategory Links (Fallback to UserDefaults)
    
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        return userDefaultsRepository.loadCategorySubcategoryLinks()
    }
    
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        userDefaultsRepository.saveCategorySubcategoryLinks(links)
    }
    
    // MARK: - Transaction-Subcategory Links (Fallback to UserDefaults)
    
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        return userDefaultsRepository.loadTransactionSubcategoryLinks()
    }
    
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        userDefaultsRepository.saveTransactionSubcategoryLinks(links)
    }
    
    // MARK: - Clear All Data
    
    func clearAllData() {
        print("⚠️ [CORE_DATA_REPO] Clearing all data")
        
        do {
            try stack.resetAllData()
            userDefaultsRepository.clearAllData()
            print("✅ [CORE_DATA_REPO] All data cleared")
        } catch {
            print("❌ [CORE_DATA_REPO] Error clearing data: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func fetchAccountSync(id: String, context: NSManagedObjectContext) -> AccountEntity? {
        let request = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    private nonisolated func fetchRecurringSeriesSync(id: String, context: NSManagedObjectContext) -> RecurringSeriesEntity? {
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
}
