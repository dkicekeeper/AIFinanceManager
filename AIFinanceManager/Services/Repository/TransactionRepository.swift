//
//  TransactionRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Transaction-specific data persistence operations

import Foundation
import CoreData

/// Protocol for transaction repository operations
protocol TransactionRepositoryProtocol {
    func loadTransactions(dateRange: DateInterval?) -> [Transaction]
    func saveTransactions(_ transactions: [Transaction])
    func saveTransactionsSync(_ transactions: [Transaction]) throws
    /// Immediately delete a single transaction from CoreData by ID (synchronous on background context).
    /// Use this for user-initiated deletions to guarantee the delete is persisted
    /// even if the app is killed shortly after.
    func deleteTransactionImmediately(id: String)
}

/// CoreData implementation of TransactionRepositoryProtocol
final class TransactionRepository: TransactionRepositoryProtocol {

    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator
    private let userDefaultsRepository: UserDefaultsRepository

    init(
        stack: CoreDataStack = .shared,
        saveCoordinator: CoreDataSaveCoordinator,
        userDefaultsRepository: UserDefaultsRepository = UserDefaultsRepository()
    ) {
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.userDefaultsRepository = userDefaultsRepository
    }

    // MARK: - Load Operations

    func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
        PerformanceProfiler.start("TransactionRepository.loadTransactions")

        // PERFORMANCE Phase 28-B: Use background context — never block the main thread for 19k entities.
        // performAndWait is synchronous but runs on the context's own serial queue (background thread).
        let bgContext = stack.newBackgroundContext()
        var transactions: [Transaction] = []

        bgContext.performAndWait {
            let request = TransactionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            // fetchBatchSize is meaningful here: CoreData loads entity data in batches of 500.
            request.fetchBatchSize = 500

            if let dateRange = dateRange {
                request.predicate = NSPredicate(
                    format: "date >= %@ AND date <= %@",
                    dateRange.start as NSDate,
                    dateRange.end as NSDate
                )
            }

            do {
                let entities = try bgContext.fetch(request)
                transactions = entities.map { $0.toTransaction() }
            } catch {
                // leave transactions empty, fallback handled below
            }
        }

        PerformanceProfiler.end("TransactionRepository.loadTransactions")

        if transactions.isEmpty {
            return userDefaultsRepository.loadTransactions(dateRange: dateRange)
        }
        return transactions
    }

    // MARK: - Save Operations

    func saveTransactions(_ transactions: [Transaction]) {
        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("TransactionRepository.saveTransactions")
            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    let fetchRequest = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
                    let existingEntities = try context.fetch(fetchRequest)

                    var existingDict: [String: TransactionEntity] = [:]
                    for entity in existingEntities {
                        if let id = entity.id, !id.isEmpty {
                            existingDict[id] = entity
                        }
                    }

                    var keptIds = Set<String>()
                    for transaction in transactions {
                        keptIds.insert(transaction.id)
                        if let existing = existingDict[transaction.id] {
                            self.updateTransactionEntity(existing, from: transaction, context: context)
                        } else {
                            let entity = TransactionEntity.from(transaction, context: context)
                            self.setTransactionRelationships(entity, from: transaction, context: context)
                        }
                    }

                    for entity in existingEntities {
                        if let id = entity.id, !keptIds.contains(id) {
                            context.delete(entity)
                        }
                    }

                    if context.hasChanges {
                        try context.save()
                    }
                    PerformanceProfiler.end("TransactionRepository.saveTransactions")
                } catch {
                    PerformanceProfiler.end("TransactionRepository.saveTransactions")
                }
            }
        }
    }

    func saveTransactionsSync(_ transactions: [Transaction]) throws {
        PerformanceProfiler.start("TransactionRepository.saveTransactionsSync")

        // PERFORMANCE: Используем background context вместо viewContext
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Выполняем все операции в background context синхронно
        try backgroundContext.performAndWait {
            // PERFORMANCE: Batch size для fetch
            let fetchRequest = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
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
            let accountFetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
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
                    updateTransactionEntity(
                        existing,
                        from: transaction,
                        accountDict: accountDict,
                        seriesDict: seriesDict
                    )
                } else {
                    // Create new
                    let newEntity = TransactionEntity.from(transaction, context: backgroundContext)
                    setTransactionRelationships(
                        newEntity,
                        from: transaction,
                        accountDict: accountDict,
                        seriesDict: seriesDict
                    )
                }

                processedCount += 1

                // PERFORMANCE: Промежуточное сохранение каждые batchSize транзакций
                if processedCount % batchSize == 0 && backgroundContext.hasChanges {
                    try backgroundContext.save()
                }
            }

            // Delete transactions that no longer exist
            for entity in existingEntities {
                if let id = entity.id, !keptIds.contains(id) {
                    backgroundContext.delete(entity)
                }
            }

            // Финальное сохранение
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("TransactionRepository.saveTransactionsSync")
    }

    // MARK: - Delete Operations

    func deleteTransactionImmediately(id: String) {
        print("🔴 [TransactionRepository.deleteTransactionImmediately] called for id=\(id)")
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let entity = try? context.fetch(request).first else {
                print("🔴 [TransactionRepository.deleteTransactionImmediately] entity NOT FOUND for id=\(id) (may not be persisted yet)")
                return
            }
            context.delete(entity)
            try? context.save()
            print("🔴 [TransactionRepository.deleteTransactionImmediately] deleted and saved for id=\(id)")
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func updateTransactionEntity(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        context: NSManagedObjectContext
    ) {
        // Mutate directly — caller is already inside context.perform { }, so nesting another
        // context.perform { } would make it async (fire-and-forget) and mutations would
        // execute AFTER context.save(), causing data loss on next launch.
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.targetAmount = transaction.targetAmount ?? 0
        entity.targetCurrency = transaction.targetCurrency
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        entity.accountName = transaction.accountName
        entity.targetAccountName = transaction.targetAccountName
        entity.accountId = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId

        // Update relationships (also direct, same context.perform block)
        if let accountId = transaction.accountId {
            entity.account = fetchAccountSync(id: accountId, context: context)
        } else {
            entity.account = nil
        }
        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = fetchAccountSync(id: targetAccountId, context: context)
        } else {
            entity.targetAccount = nil
        }
        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = fetchRecurringSeriesSync(id: seriesId, context: context)
        } else {
            entity.recurringSeries = nil
        }
    }

    private nonisolated func updateTransactionEntity(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        accountDict: [String: AccountEntity],
        seriesDict: [String: RecurringSeriesEntity]
    ) {
        // Direct mutations — caller is already inside performAndWait { }, so nesting another
        // async perform { } would fire-and-forget and mutations would execute AFTER save(),
        // causing data loss on next launch.
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.targetAmount = transaction.targetAmount ?? 0
        entity.targetCurrency = transaction.targetCurrency
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        entity.accountName = transaction.accountName
        entity.accountId = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId
        entity.targetAccountName = transaction.targetAccountName

        // Set relationships using pre-fetched dictionaries
        if let accountId = transaction.accountId {
            entity.account = accountDict[accountId]
        } else {
            entity.account = nil
        }

        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = accountDict[targetAccountId]
        } else {
            entity.targetAccount = nil
        }

        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = seriesDict[seriesId]
        } else {
            entity.recurringSeries = nil
        }
    }

    private nonisolated func setTransactionRelationships(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        context: NSManagedObjectContext
    ) {
        // Direct mutations — caller is already inside context.perform { }
        if let accountId = transaction.accountId {
            entity.account = fetchAccountSync(id: accountId, context: context)
        }
        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = fetchAccountSync(id: targetAccountId, context: context)
        }
        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = fetchRecurringSeriesSync(id: seriesId, context: context)
        }
    }

    private nonisolated func setTransactionRelationships(
        _ entity: TransactionEntity,
        from transaction: Transaction,
        accountDict: [String: AccountEntity],
        seriesDict: [String: RecurringSeriesEntity]
    ) {
        // Direct mutations — caller is already inside performAndWait { }, so nesting another
        // async perform { } would fire-and-forget and mutations would execute AFTER save(),
        // causing data loss on next launch.
        if let accountId = transaction.accountId {
            entity.account = accountDict[accountId]
        }

        if let targetAccountId = transaction.targetAccountId {
            entity.targetAccount = accountDict[targetAccountId]
        }

        if let seriesId = transaction.recurringSeriesId {
            entity.recurringSeries = seriesDict[seriesId]
        }
    }

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
