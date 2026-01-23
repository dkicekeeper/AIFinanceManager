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
        
        // CRITICAL: Use viewContext for immediate save to prevent data loss
        // This ensures data is persisted even if app terminates quickly
        let context = stack.viewContext
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveAccounts")
            
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
                    print("✅ [CORE_DATA_REPO] Accounts saved successfully")
                }
            } catch {
                print("❌ [CORE_DATA_REPO] Error saving accounts: \(error)")
            }
            
            PerformanceProfiler.end("CoreDataRepository.saveAccounts")
        }
    }
    
    // MARK: - Recurring Series
    
    func loadRecurringSeries() -> [RecurringSeries] {
        print("📂 [CORE_DATA_REPO] Loading recurring series from Core Data")
        PerformanceProfiler.start("CoreDataRepository.loadRecurringSeries")
        
        let context = stack.viewContext
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            let series = entities.map { $0.toRecurringSeries() }
            
            PerformanceProfiler.end("CoreDataRepository.loadRecurringSeries")
            print("✅ [CORE_DATA_REPO] Loaded \(series.count) recurring series")
            
            return series
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading recurring series: \(error)")
            PerformanceProfiler.end("CoreDataRepository.loadRecurringSeries")
            
            // Fallback to UserDefaults if Core Data fails
            print("⚠️ [CORE_DATA_REPO] Falling back to UserDefaults")
            return userDefaultsRepository.loadRecurringSeries()
        }
    }
    
    func saveRecurringSeries(_ series: [RecurringSeries]) {
        print("💾 [CORE_DATA_REPO] Saving \(series.count) recurring series to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveRecurringSeries")
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing recurring series
                    let fetchRequest = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create recurring series
                    for item in series {
                        keptIds.insert(item.id)
                        
                        if let existing = existingDict[item.id] {
                            // Update existing
                            existing.isActive = item.isActive
                            existing.amount = NSDecimalNumber(decimal: item.amount)
                            existing.currency = item.currency
                            existing.category = item.category
                            existing.subcategory = item.subcategory
                            existing.descriptionText = item.description
                            existing.frequency = item.frequency.rawValue
                            existing.startDate = DateFormatters.dateFormatter.date(from: item.startDate)
                            existing.lastGeneratedDate = item.lastGeneratedDate.flatMap { DateFormatters.dateFormatter.date(from: $0) }
                            existing.kind = item.kind.rawValue
                            existing.brandLogo = item.brandLogo?.rawValue
                            existing.brandId = item.brandId
                            existing.status = item.status?.rawValue
                            
                            // Update account relationship if needed
                            if let accountId = item.accountId {
                                existing.account = self.fetchAccountSync(id: accountId, context: context)
                            }
                        } else {
                            // Create new
                            let entity = RecurringSeriesEntity.from(item, context: context)
                            
                            // Set account relationship if needed
                            if let accountId = item.accountId {
                                entity.account = self.fetchAccountSync(id: accountId, context: context)
                            }
                        }
                    }
                    
                    // Delete recurring series that no longer exist
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
                    print("❌ [CORE_DATA_REPO] Error saving recurring series: \(error)")
                }
            }
            
            PerformanceProfiler.end("CoreDataRepository.saveRecurringSeries")
            print("✅ [CORE_DATA_REPO] Recurring series saved successfully")
        }
    }
    
    // MARK: - Categories
    
    func loadCategories() -> [CustomCategory] {
        print("📂 [CORE_DATA_REPO] Loading categories from Core Data")
        PerformanceProfiler.start("CoreDataRepository.loadCategories")
        
        let context = stack.viewContext
        let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let categories = entities.map { $0.toCustomCategory() }
            
            PerformanceProfiler.end("CoreDataRepository.loadCategories")
            print("✅ [CORE_DATA_REPO] Loaded \(categories.count) categories")
            
            return categories
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading categories: \(error)")
            PerformanceProfiler.end("CoreDataRepository.loadCategories")
            
            // Fallback to UserDefaults if Core Data fails
            print("⚠️ [CORE_DATA_REPO] Falling back to UserDefaults")
            return userDefaultsRepository.loadCategories()
        }
    }
    
    func saveCategories(_ categories: [CustomCategory]) {
        print("💾 [CORE_DATA_REPO] Saving \(categories.count) categories to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveCategories")
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing categories
                    let fetchRequest = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create categories
                    for category in categories {
                        keptIds.insert(category.id)
                        
                        if let existing = existingDict[category.id] {
                            // Update existing
                            existing.name = category.name
                            existing.type = category.type.rawValue
                            existing.iconName = category.iconName
                            existing.colorHex = category.colorHex
                        } else {
                            // Create new
                            _ = CustomCategoryEntity.from(category, context: context)
                        }
                    }
                    
                    // Delete categories that no longer exist
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
                    print("❌ [CORE_DATA_REPO] Error saving categories: \(error)")
                }
            }
            
            PerformanceProfiler.end("CoreDataRepository.saveCategories")
            print("✅ [CORE_DATA_REPO] Categories saved successfully")
        }
    }
    
    // MARK: - Category Rules
    
    func loadCategoryRules() -> [CategoryRule] {
        print("📂 [CORE_DATA_REPO] Loading category rules from Core Data")
        
        let context = stack.viewContext
        let request = NSFetchRequest<CategoryRuleEntity>(entityName: "CategoryRuleEntity")
        request.predicate = NSPredicate(format: "isEnabled == YES")
        
        do {
            let entities = try context.fetch(request)
            let rules = entities.map { $0.toCategoryRule() }
            print("✅ [CORE_DATA_REPO] Loaded \(rules.count) category rules")
            return rules
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading category rules: \(error)")
            return userDefaultsRepository.loadCategoryRules()
        }
    }
    
    func saveCategoryRules(_ rules: [CategoryRule]) {
        print("💾 [CORE_DATA_REPO] Saving \(rules.count) category rules to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing rules
                    let fetchRequest = NSFetchRequest<CategoryRuleEntity>(entityName: "CategoryRuleEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Delete all existing rules
                    for entity in existingEntities {
                        context.delete(entity)
                    }
                    
                    // Create new rules
                    for rule in rules {
                        _ = CategoryRuleEntity.from(rule, context: context)
                    }
                    
                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    print("❌ [CORE_DATA_REPO] Error saving category rules: \(error)")
                }
            }
            
            print("✅ [CORE_DATA_REPO] Category rules saved successfully")
        }
    }
    
    // MARK: - Recurring Occurrences (Fallback to UserDefaults)
    
    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        return userDefaultsRepository.loadRecurringOccurrences()
    }
    
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {
        userDefaultsRepository.saveRecurringOccurrences(occurrences)
    }
    
    // MARK: - Subcategories
    
    func loadSubcategories() -> [Subcategory] {
        print("📂 [CORE_DATA_REPO] Loading subcategories from Core Data")
        
        let context = stack.viewContext
        let request = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let subcategories = entities.map { $0.toSubcategory() }
            print("✅ [CORE_DATA_REPO] Loaded \(subcategories.count) subcategories")
            return subcategories
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading subcategories: \(error)")
            return userDefaultsRepository.loadSubcategories()
        }
    }
    
    func saveSubcategories(_ subcategories: [Subcategory]) {
        print("💾 [CORE_DATA_REPO] Saving \(subcategories.count) subcategories to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing subcategories
                    let fetchRequest = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create subcategories
                    for subcategory in subcategories {
                        keptIds.insert(subcategory.id)
                        
                        if let existing = existingDict[subcategory.id] {
                            // Update existing
                            existing.name = subcategory.name
                        } else {
                            // Create new
                            _ = SubcategoryEntity.from(subcategory, context: context)
                        }
                    }
                    
                    // Delete subcategories that no longer exist
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
                    print("❌ [CORE_DATA_REPO] Error saving subcategories: \(error)")
                }
            }
            
            print("✅ [CORE_DATA_REPO] Subcategories saved successfully")
        }
    }
    
    // MARK: - Category-Subcategory Links
    
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        print("📂 [CORE_DATA_REPO] Loading category-subcategory links from Core Data")
        
        let context = stack.viewContext
        let request = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "categoryId", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let links = entities.map { $0.toCategorySubcategoryLink() }
            print("✅ [CORE_DATA_REPO] Loaded \(links.count) category-subcategory links")
            return links
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading category-subcategory links: \(error)")
            return userDefaultsRepository.loadCategorySubcategoryLinks()
        }
    }
    
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        print("💾 [CORE_DATA_REPO] Saving \(links.count) category-subcategory links to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing links
                    let fetchRequest = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create links
                    for link in links {
                        keptIds.insert(link.id)
                        
                        if let existing = existingDict[link.id] {
                            // Update existing
                            existing.categoryId = link.categoryId
                            existing.subcategoryId = link.subcategoryId
                        } else {
                            // Create new
                            _ = CategorySubcategoryLinkEntity.from(link, context: context)
                        }
                    }
                    
                    // Delete links that no longer exist
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
                    print("❌ [CORE_DATA_REPO] Error saving category-subcategory links: \(error)")
                }
            }
            
            print("✅ [CORE_DATA_REPO] Category-subcategory links saved successfully")
        }
    }
    
    // MARK: - Transaction-Subcategory Links
    
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        print("📂 [CORE_DATA_REPO] Loading transaction-subcategory links from Core Data")
        
        let context = stack.viewContext
        let request = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "transactionId", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let links = entities.map { $0.toTransactionSubcategoryLink() }
            print("✅ [CORE_DATA_REPO] Loaded \(links.count) transaction-subcategory links")
            return links
        } catch {
            print("❌ [CORE_DATA_REPO] Error loading transaction-subcategory links: \(error)")
            return userDefaultsRepository.loadTransactionSubcategoryLinks()
        }
    }
    
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        print("💾 [CORE_DATA_REPO] Saving \(links.count) transaction-subcategory links to Core Data")
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing links
                    let fetchRequest = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    let existingDict = Dictionary(uniqueKeysWithValues: existingEntities.map { ($0.id ?? "", $0) })
                    
                    var keptIds = Set<String>()
                    
                    // Update or create links
                    for link in links {
                        keptIds.insert(link.id)
                        
                        if let existing = existingDict[link.id] {
                            // Update existing
                            existing.transactionId = link.transactionId
                            existing.subcategoryId = link.subcategoryId
                        } else {
                            // Create new
                            _ = TransactionSubcategoryLinkEntity.from(link, context: context)
                        }
                    }
                    
                    // Delete links that no longer exist
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
                    print("❌ [CORE_DATA_REPO] Error saving transaction-subcategory links: \(error)")
                }
            }
            
            print("✅ [CORE_DATA_REPO] Transaction-subcategory links saved successfully")
        }
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
