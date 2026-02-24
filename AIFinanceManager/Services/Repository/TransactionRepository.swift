//
//  TransactionRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Transaction-specific data persistence operations

import Foundation
import CoreData
import os

/// Protocol for transaction repository operations
protocol TransactionRepositoryProtocol {
    func loadTransactions(dateRange: DateInterval?) -> [Transaction]
    func saveTransactions(_ transactions: [Transaction])
    func saveTransactionsSync(_ transactions: [Transaction]) throws
    /// Immediately delete a single transaction from CoreData by ID (synchronous on background context).
    /// Use this for user-initiated deletions to guarantee the delete is persisted
    /// even if the app is killed shortly after.
    func deleteTransactionImmediately(id: String)
    /// Insert a single new transaction. O(1) — does NOT fetch existing records.
    func insertTransaction(_ transaction: Transaction)
    /// Update fields of an existing transaction by ID. O(1) — fetches by PK only.
    func updateTransactionFields(_ transaction: Transaction)
    /// Batch-insert using NSBatchInsertRequest. O(N) — ideal for CSV import.
    func batchInsertTransactions(_ transactions: [Transaction])
}

/// CoreData implementation of TransactionRepositoryProtocol
final class TransactionRepository: TransactionRepositoryProtocol {

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "TransactionRepository")

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
        // Note: relationshipKeyPathsForPrefetching ["account", "targetAccount"] was removed.
        // toTransaction() uses string column fallbacks (accountId, accountName, etc.) for all
        // critical fields, so relationship faults are only triggered for legacy data.
        // Faults fire safely inside the performAndWait block; no batch prefetch needed.
        let bgContext = stack.newBackgroundContext()
        var transactions: [Transaction] = []
        var loadError: Error? = nil

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
                loadError = error
            }
        }

        PerformanceProfiler.end("TransactionRepository.loadTransactions")

        if loadError != nil {
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
        Self.logger.debug("🔵 [TransactionRepository] deleteTransactionImmediately called for id: \(id, privacy: .public)")
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let entity = try? context.fetch(request).first else {
                Self.logger.warning("⚠️ [TransactionRepository] deleteTransactionImmediately: entity NOT FOUND for id: \(id, privacy: .public) (may not be persisted yet)")
                return
            }
            context.delete(entity)
            try? context.save()
            Self.logger.debug("✅ [TransactionRepository] deleteTransactionImmediately: deleted and saved for id: \(id, privacy: .public)")
        }
    }

    // MARK: - Targeted Persist Methods (Phase 28-C)

    func insertTransaction(_ transaction: Transaction) {
        let bgContext = stack.newBackgroundContext()
        bgContext.performAndWait {
            // Create entity from Transaction model
            let entity = TransactionEntity.from(transaction, context: bgContext)

            // Resolve account relationship (best-effort; accountId String is the fallback)
            if let accountId = transaction.accountId, !accountId.isEmpty {
                let req = AccountEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", accountId)
                req.fetchLimit = 1
                entity.account = try? bgContext.fetch(req).first
            }

            if let targetId = transaction.targetAccountId, !targetId.isEmpty {
                let req = AccountEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", targetId)
                req.fetchLimit = 1
                entity.targetAccount = try? bgContext.fetch(req).first
            }

            if let seriesId = transaction.recurringSeriesId, !seriesId.isEmpty {
                let req = RecurringSeriesEntity.fetchRequest()
                req.predicate = NSPredicate(format: "id == %@", seriesId)
                req.fetchLimit = 1
                entity.recurringSeries = try? bgContext.fetch(req).first
            }

            do {
                try bgContext.save()
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] insertTransaction save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func updateTransactionFields(_ transaction: Transaction) {
        let bgContext = stack.newBackgroundContext()
        // performAndWait (synchronous) — same reasoning as insertTransaction:
        // ensures the update completes before any subsequent deleteTransactionImmediately
        // on the same entity, preventing a race that leaves a stale CoreData record.
        bgContext.performAndWait {
            let req = TransactionEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", transaction.id)
            req.fetchLimit = 1
            guard let entity = (try? bgContext.fetch(req))?.first else { return }

            entity.date             = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
            entity.descriptionText  = transaction.description
            entity.amount           = transaction.amount
            entity.currency         = transaction.currency
            entity.convertedAmount  = transaction.convertedAmount ?? 0
            entity.type             = transaction.type.rawValue
            entity.category         = transaction.category
            entity.subcategory      = transaction.subcategory
            entity.targetAmount     = transaction.targetAmount ?? 0
            entity.targetCurrency   = transaction.targetCurrency
            entity.accountId        = transaction.accountId
            entity.targetAccountId  = transaction.targetAccountId
            entity.accountName      = transaction.accountName
            entity.targetAccountName = transaction.targetAccountName
            entity.createdAt        = Date(timeIntervalSince1970: transaction.createdAt)

            // Sync recurringSeries relationship
            if let seriesId = transaction.recurringSeriesId, !seriesId.isEmpty {
                let seriesReq = RecurringSeriesEntity.fetchRequest()
                seriesReq.predicate = NSPredicate(format: "id == %@", seriesId)
                seriesReq.fetchLimit = 1
                entity.recurringSeries = (try? bgContext.fetch(seriesReq))?.first
            } else {
                entity.recurringSeries = nil
            }

            do {
                try bgContext.save()
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] updateTransactionFields save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func batchInsertTransactions(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        let bgContext = stack.newBackgroundContext()
        bgContext.perform {
            // NSBatchInsertRequest (iOS 14+): inserts directly into SQLite,
            // bypassing NSManagedObject lifecycle — ideal for CSV import of 1k+ records.
            // Relationships are NOT set; toTransaction() uses accountId/targetAccountId String columns.
            //
            // IMPORTANT: willSave() is NOT called for NSBatchInsertRequest, so dateSectionKey
            // must be set explicitly here. Without it every batch-imported record has nil
            // dateSectionKey, causing AppCoordinator.backfillDateSectionKeysIfNeeded() to run
            // on every subsequent launch (~700ms per launch for 18k transactions).
            let dicts: [[String: Any]] = transactions.map { tx in
                var dict: [String: Any] = [:]
                dict["id"]               = tx.id
                let dateValue            = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
                dict["date"]             = dateValue
                // Set dateSectionKey explicitly — NSBatchInsertRequest bypasses willSave(),
                // so the automatic TransactionEntity+SectionKey.swift override never fires.
                dict["dateSectionKey"]   = TransactionSectionKeyFormatter.string(from: dateValue)
                dict["descriptionText"]  = tx.description
                dict["amount"]           = tx.amount
                dict["currency"]         = tx.currency
                dict["convertedAmount"]  = tx.convertedAmount ?? 0.0
                dict["type"]             = tx.type.rawValue
                dict["category"]         = tx.category
                dict["subcategory"]      = tx.subcategory ?? ""
                dict["targetAmount"]     = tx.targetAmount ?? 0.0
                dict["targetCurrency"]   = tx.targetCurrency ?? ""
                dict["accountId"]        = tx.accountId ?? ""
                dict["targetAccountId"]  = tx.targetAccountId ?? ""
                dict["accountName"]      = tx.accountName ?? ""
                dict["targetAccountName"] = tx.targetAccountName ?? ""
                dict["createdAt"]        = Date(timeIntervalSince1970: tx.createdAt)
                return dict
            }

            let insertRequest = NSBatchInsertRequest(entityName: "TransactionEntity", objects: dicts)
            insertRequest.resultType = .objectIDs  // needed for viewContext merge in Task 7

            // NOTE: recurringSeries relationships are intentionally omitted here. NSBatchInsertRequest
            // bypasses NSManagedObject lifecycle and cannot resolve managed-object relationships.
            // toTransaction() uses the recurringSeriesId String column as a fallback, which is sufficient.
            do {
                let result = try bgContext.execute(insertRequest) as? NSBatchInsertResult
                // Merge inserted object IDs into viewContext so @Observable picks them up.
                // Must be dispatched to main queue because viewContext is main-thread-only.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.stack.mergeBatchInsertResult(result)
                }
            } catch {
                Self.logger.error("⚠️ [TransactionRepository] batchInsertTransactions failed: \(error.localizedDescription, privacy: .public)")
            }
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
