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
    
    /// Save coordinator to prevent race conditions
    private let saveCoordinator = CoreDataSaveCoordinator()
    
    // MARK: - Initialization
    
    init() {
    }
    
    // MARK: - Transactions
    
    func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
        if let dateRange = dateRange {
        } else {
        }
        PerformanceProfiler.start("CoreDataRepository.loadTransactions")

        let context = stack.viewContext
        let request = TransactionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        // PERFORMANCE: Batch size для ленивой загрузки объектов
        request.fetchBatchSize = 100

        // PERFORMANCE: Prefetch relationships чтобы избежать N+1 проблемы
        request.relationshipKeyPathsForPrefetching = ["account"]

        // Apply date range filter if provided
        if let dateRange = dateRange {
            request.predicate = NSPredicate(
                format: "date >= %@ AND date <= %@",
                dateRange.start as NSDate,
                dateRange.end as NSDate
            )
        }

        do {
            let entities = try context.fetch(request)
            let transactions = entities.map { $0.toTransaction() }

            PerformanceProfiler.end("CoreDataRepository.loadTransactions")

            return transactions
        } catch {
            PerformanceProfiler.end("CoreDataRepository.loadTransactions")

            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadTransactions(dateRange: dateRange)
        }
    }
    
    func saveTransactions(_ transactions: [Transaction]) {
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveTransactions")
            
            do {
                try await self.saveCoordinator.performSave(operation: "saveTransactions") { context in
                    // First, fetch all existing transactions to update or delete
                    let fetchRequest = TransactionEntity.fetchRequest()
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    var existingDict: [String: TransactionEntity] = [:]
                    for entity in existingEntities {
                        if let id = entity.id, !id.isEmpty {
                            existingDict[id] = entity
                        }
                    }
                    
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
                }
                
                PerformanceProfiler.end("CoreDataRepository.saveTransactions")
                
            } catch {
                PerformanceProfiler.end("CoreDataRepository.saveTransactions")
            }
        }
    }
    
    // MARK: - Accounts
    
    func loadAccounts() -> [Account] {
        PerformanceProfiler.start("CoreDataRepository.loadAccounts")
        
        let context = stack.viewContext
        let request = AccountEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let accounts = entities.map { $0.toAccount() }
            
            PerformanceProfiler.end("CoreDataRepository.loadAccounts")
            
            return accounts
        } catch {
            PerformanceProfiler.end("CoreDataRepository.loadAccounts")
            
            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadAccounts()
        }
    }
    
    func saveAccounts(_ accounts: [Account]) {
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveAccounts")
            
            do {
                try await self.saveCoordinator.performSave(operation: "saveAccounts") { context in
                    // Fetch all existing accounts
                    let fetchRequest = AccountEntity.fetchRequest()
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: AccountEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
                
                PerformanceProfiler.end("CoreDataRepository.saveAccounts")
                
            } catch {
                PerformanceProfiler.end("CoreDataRepository.saveAccounts")
            }
        }
    }
    
    /// Синхронно сохранить счета в Core Data (для импорта CSV)
    func saveAccountsSync(_ accounts: [Account]) throws {
        
        let context = stack.viewContext
        
        // Fetch all existing accounts
        let fetchRequest = AccountEntity.fetchRequest()
        let existingEntities = try context.fetch(fetchRequest)
        
        // Build dictionary safely, handling duplicates by keeping the first occurrence
        var existingDict: [String: AccountEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
                // Found duplicate - delete the extra entity
                context.delete(entity)
            }
        }
        
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
        } else {
        }
    }
    
    /// Синхронно сохранить транзакции в Core Data (для импорта CSV)
    /// ОПТИМИЗИРОВАНО: Использует background context для избежания блокировки UI
    func saveTransactionsSync(_ transactions: [Transaction]) throws {
        PerformanceProfiler.start("CoreDataRepository.saveTransactionsSync")

        // PERFORMANCE: Используем background context вместо viewContext
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Выполняем все операции в background context синхронно
        try backgroundContext.performAndWait {
            // PERFORMANCE: Batch size для fetch
            let fetchRequest = TransactionEntity.fetchRequest()
            fetchRequest.fetchBatchSize = 500

            let existingEntities = try backgroundContext.fetch(fetchRequest)

            // Build dictionary safely
            var existingDict: [String: TransactionEntity] = [:]
            for entity in existingEntities {
                let id = entity.id ?? ""
                if !id.isEmpty && existingDict[id] == nil {
                    existingDict[id] = entity
                } else if !id.isEmpty {
                    backgroundContext.delete(entity)
                }
            }

            // Fetch all existing accounts to establish relationships
            let accountFetchRequest = AccountEntity.fetchRequest()
            let accountEntities = try backgroundContext.fetch(accountFetchRequest)
            var accountDict: [String: AccountEntity] = [:]
            for accountEntity in accountEntities {
                if let id = accountEntity.id {
                    accountDict[id] = accountEntity
                }
            }

            // Fetch all existing recurring series to establish relationships
            let seriesFetchRequest = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
            let seriesEntities = try backgroundContext.fetch(seriesFetchRequest)
            var seriesDict: [String: RecurringSeriesEntity] = [:]
            for seriesEntity in seriesEntities {
                if let id = seriesEntity.id {
                    seriesDict[id] = seriesEntity
                }
            }

            var keptIds = Set<String>()

            // PERFORMANCE: Batch processing - сохраняем каждые 500 транзакций
            let batchSize = 500
            var processedCount = 0

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

                    // Установить relationships
                    if let accountId = transaction.accountId {
                        existing.account = accountDict[accountId]
                    } else {
                        existing.account = nil
                    }

                    if let targetAccountId = transaction.targetAccountId {
                        existing.targetAccount = accountDict[targetAccountId]
                    } else {
                        existing.targetAccount = nil
                    }

                    if let seriesId = transaction.recurringSeriesId {
                        existing.recurringSeries = seriesDict[seriesId]
                    } else {
                        existing.recurringSeries = nil
                    }
                } else {
                    // Create new
                    let newEntity = TransactionEntity.from(transaction, context: backgroundContext)

                    // Установить relationships для новой транзакции
                    if let accountId = transaction.accountId {
                        newEntity.account = accountDict[accountId]
                    }

                    if let targetAccountId = transaction.targetAccountId {
                        newEntity.targetAccount = accountDict[targetAccountId]
                    }

                    if let seriesId = transaction.recurringSeriesId {
                        newEntity.recurringSeries = seriesDict[seriesId]
                    }
                }

                processedCount += 1

                // PERFORMANCE: Промежуточное сохранение каждые batchSize транзакций
                if processedCount % batchSize == 0 && backgroundContext.hasChanges {
                    try backgroundContext.save()
                    backgroundContext.reset() // Освобождаем память

                    // Перезагружаем dictionaries после reset
                    let refetchedEntities = try backgroundContext.fetch(fetchRequest)
                    existingDict.removeAll()
                    for entity in refetchedEntities {
                        if let id = entity.id, !id.isEmpty {
                            existingDict[id] = entity
                        }
                    }

                    let refetchedAccounts = try backgroundContext.fetch(accountFetchRequest)
                    accountDict.removeAll()
                    for entity in refetchedAccounts {
                        if let id = entity.id {
                            accountDict[id] = entity
                        }
                    }

                    let refetchedSeries = try backgroundContext.fetch(seriesFetchRequest)
                    seriesDict.removeAll()
                    for entity in refetchedSeries {
                        if let id = entity.id {
                            seriesDict[id] = entity
                        }
                    }

                }
            }

            // Delete transactions that no longer exist
            // Перезагружаем существующие entities после возможного reset
            let finalExistingEntities = try backgroundContext.fetch(fetchRequest)
            for entity in finalExistingEntities {
                if let id = entity.id, !keptIds.contains(id) {
                    backgroundContext.delete(entity)
                }
            }

            // Финальное сохранение
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            } else {
            }
        }

        PerformanceProfiler.end("CoreDataRepository.saveTransactionsSync")
    }
    
    /// Синхронно сохранить категории в Core Data (для импорта CSV)
    func saveCategoriesSync(_ categories: [CustomCategory]) throws {
        
        let context = stack.viewContext
        
        // Fetch all existing categories
        let fetchRequest = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        let existingEntities = try context.fetch(fetchRequest)
        
        // Build dictionary safely
        var existingDict: [String: CustomCategoryEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
                context.delete(entity)
            }
        }
        
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
        } else {
        }
    }
    
    // MARK: - Recurring Series
    
    func loadRecurringSeries() -> [RecurringSeries] {
        PerformanceProfiler.start("CoreDataRepository.loadRecurringSeries")
        
        let context = stack.viewContext
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            let series = entities.map { $0.toRecurringSeries() }
            
            PerformanceProfiler.end("CoreDataRepository.loadRecurringSeries")
            
            return series
        } catch {
            PerformanceProfiler.end("CoreDataRepository.loadRecurringSeries")
            
            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadRecurringSeries()
        }
    }
    
    func saveRecurringSeries(_ series: [RecurringSeries]) {
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveRecurringSeries")
            
            do {
                try await self.saveCoordinator.performSave(operation: "saveRecurringSeries") { context in
                    // Fetch all existing recurring series
                    let fetchRequest = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: RecurringSeriesEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
                
                PerformanceProfiler.end("CoreDataRepository.saveRecurringSeries")
                
            } catch {
                PerformanceProfiler.end("CoreDataRepository.saveRecurringSeries")
            }
        }
    }
    
    // MARK: - Categories
    
    func loadCategories() -> [CustomCategory] {
        PerformanceProfiler.start("CoreDataRepository.loadCategories")
        
        let context = stack.viewContext
        let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let categories = entities.map { $0.toCustomCategory() }
            
            PerformanceProfiler.end("CoreDataRepository.loadCategories")
            
            return categories
        } catch {
            PerformanceProfiler.end("CoreDataRepository.loadCategories")
            
            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadCategories()
        }
    }
    
    func saveCategories(_ categories: [CustomCategory]) {
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            PerformanceProfiler.start("CoreDataRepository.saveCategories")
            
            do {
                try await self.saveCoordinator.performSave(operation: "saveCategories") { context in
                    // Fetch all existing categories
                    let fetchRequest = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: CustomCategoryEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
                
                PerformanceProfiler.end("CoreDataRepository.saveCategories")
                
            } catch {
                PerformanceProfiler.end("CoreDataRepository.saveCategories")
            }
        }
    }
    
    // MARK: - Category Rules
    
    func loadCategoryRules() -> [CategoryRule] {
        
        let context = stack.viewContext
        let request = NSFetchRequest<CategoryRuleEntity>(entityName: "CategoryRuleEntity")
        request.predicate = NSPredicate(format: "isEnabled == YES")
        
        do {
            let entities = try context.fetch(request)
            let rules = entities.map { $0.toCategoryRule() }
            return rules
        } catch {
            return userDefaultsRepository.loadCategoryRules()
        }
    }
    
    func saveCategoryRules(_ rules: [CategoryRule]) {
        
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
                }
            }
            
        }
    }
    
    // MARK: - Recurring Occurrences

    func loadRecurringOccurrences() -> [RecurringOccurrence] {

        let context = stack.viewContext
        let request = NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "occurrenceDate", ascending: false)]

        do {
            let entities = try context.fetch(request)
            let occurrences = entities.map { $0.toRecurringOccurrence() }
            return occurrences
        } catch {

            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadRecurringOccurrences()
        }
    }

    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {

        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("CoreDataRepository.saveRecurringOccurrences")

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    // Fetch all existing occurrences
                    let fetchRequest = NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: RecurringOccurrenceEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }

                    var keptIds = Set<String>()

                    // Update or create occurrences
                    for occurrence in occurrences {
                        keptIds.insert(occurrence.id)

                        if let existing = existingDict[occurrence.id] {
                            // Update existing
                            existing.seriesId = occurrence.seriesId
                            existing.occurrenceDate = occurrence.occurrenceDate
                            existing.transactionId = occurrence.transactionId

                            // Update series relationship if needed
                            existing.series = self.fetchRecurringSeriesSync(id: occurrence.seriesId, context: context)
                        } else {
                            // Create new
                            let entity = RecurringOccurrenceEntity.from(occurrence, context: context)

                            // Set series relationship
                            entity.series = self.fetchRecurringSeriesSync(id: occurrence.seriesId, context: context)
                        }
                    }

                    // Delete occurrences that no longer exist
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
                }
            }

            PerformanceProfiler.end("CoreDataRepository.saveRecurringOccurrences")
        }
    }
    
    // MARK: - Subcategories
    
    func loadSubcategories() -> [Subcategory] {
        
        let context = stack.viewContext
        let request = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let subcategories = entities.map { $0.toSubcategory() }
            return subcategories
        } catch {
            return userDefaultsRepository.loadSubcategories()
        }
    }
    
    func saveSubcategories(_ subcategories: [Subcategory]) {
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing subcategories
                    let fetchRequest = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: SubcategoryEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
            }
            
        }
    }
    
    // MARK: - Category-Subcategory Links
    
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        
        let context = stack.viewContext
        let request = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "categoryId", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let links = entities.map { $0.toCategorySubcategoryLink() }
            return links
        } catch {
            return userDefaultsRepository.loadCategorySubcategoryLinks()
        }
    }
    
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing links
                    let fetchRequest = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: CategorySubcategoryLinkEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
            }
            
        }
    }
    
    // MARK: - Transaction-Subcategory Links
    
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        
        let context = stack.viewContext
        let request = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "transactionId", ascending: true)]
        
        do {
            let entities = try context.fetch(request)
            let links = entities.map { $0.toTransactionSubcategoryLink() }
            return links
        } catch {
            return userDefaultsRepository.loadTransactionSubcategoryLinks()
        }
    }
    
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }
            
            let context = self.stack.newBackgroundContext()
            
            await context.perform {
                do {
                    // Fetch all existing links
                    let fetchRequest = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
                    let existingEntities = try context.fetch(fetchRequest)
                    
                    // Build dictionary safely, handling duplicates by keeping the first occurrence
                    var existingDict: [String: TransactionSubcategoryLinkEntity] = [:]
                    for entity in existingEntities {
                        let id = entity.id ?? ""
                        if !id.isEmpty && existingDict[id] == nil {
                            existingDict[id] = entity
                        } else if !id.isEmpty {
                            // Found duplicate - delete the extra entity
                            context.delete(entity)
                        }
                    }
                    
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
                }
            }
            
        }
    }
    
    // MARK: - Clear All Data
    
    func clearAllData() {
        
        do {
            try stack.resetAllData()
            userDefaultsRepository.clearAllData()
        } catch {
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
