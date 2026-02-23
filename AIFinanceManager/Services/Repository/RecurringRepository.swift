//
//  RecurringRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Recurring transaction-specific data persistence operations

import Foundation
import CoreData

/// Protocol for recurring transaction repository operations
protocol RecurringRepositoryProtocol {
    func loadRecurringSeries() -> [RecurringSeries]
    func saveRecurringSeries(_ series: [RecurringSeries])
    func loadRecurringOccurrences() -> [RecurringOccurrence]
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])
}

/// CoreData implementation of RecurringRepositoryProtocol
final class RecurringRepository: RecurringRepositoryProtocol {

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

    // MARK: - Recurring Series

    func loadRecurringSeries() -> [RecurringSeries] {
        PerformanceProfiler.start("RecurringRepository.loadRecurringSeries")

        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var series: [RecurringSeries] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]

            do {
                let entities = try bgContext.fetch(request)
                series = entities.map { $0.toRecurringSeries() }
            } catch {
                loadError = error
            }
        }

        PerformanceProfiler.end("RecurringRepository.loadRecurringSeries")

        if loadError != nil {
            // Fallback to UserDefaults if Core Data fetch failed
            return userDefaultsRepository.loadRecurringSeries()
        }
        return series
    }

    func saveRecurringSeries(_ series: [RecurringSeries]) {

        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("RecurringRepository.saveRecurringSeries")

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    // Fetch all existing recurring series
                    let fetchRequest = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
                    let existingEntities = try context.fetch(fetchRequest)

                    // Build dictionary safely, handling duplicates
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

                    // Pre-fetch all needed accounts in one query (fixes N+1)
                    let neededAccountIds = series.compactMap { $0.accountId }.filter { !$0.isEmpty }
                    var accountDict: [String: AccountEntity] = [:]
                    if !neededAccountIds.isEmpty {
                        let accountRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
                        accountRequest.predicate = NSPredicate(format: "id IN %@", neededAccountIds)
                        accountRequest.fetchBatchSize = 50
                        if let fetchedAccounts = try? context.fetch(accountRequest) {
                            for account in fetchedAccounts {
                                if let accountId = account.id {
                                    accountDict[accountId] = account
                                }
                            }
                        }
                    }

                    // Update or create recurring series
                    for item in series {
                        keptIds.insert(item.id)

                        if let existing = existingDict[item.id] {
                            // Update existing
                            self.updateRecurringSeriesEntity(existing, from: item, accountDict: accountDict, context: context)
                        } else {
                            // Create new
                            let entity = RecurringSeriesEntity.from(item, context: context)

                            // Set account relationship if needed
                            entity.account = accountDict[item.accountId ?? ""]
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

                    PerformanceProfiler.end("RecurringRepository.saveRecurringSeries")
                } catch {
                    PerformanceProfiler.end("RecurringRepository.saveRecurringSeries")
                }
            }
        }
    }

    // MARK: - Recurring Occurrences

    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var occurrences: [RecurringOccurrence] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "occurrenceDate", ascending: false)]

            do {
                let entities = try bgContext.fetch(request)
                occurrences = entities.map { $0.toRecurringOccurrence() }
            } catch {
                loadError = error
            }
        }

        if loadError != nil {
            // Fallback to UserDefaults if Core Data fetch failed
            return userDefaultsRepository.loadRecurringOccurrences()
        }
        return occurrences
    }

    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {

        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("RecurringRepository.saveRecurringOccurrences")

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    // Fetch all existing occurrences
                    let fetchRequest = NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
                    let existingEntities = try context.fetch(fetchRequest)

                    // Build dictionary safely, handling duplicates
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
                            // Direct mutations — caller is already inside context.perform
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

            PerformanceProfiler.end("RecurringRepository.saveRecurringOccurrences")
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func updateRecurringSeriesEntity(
        _ entity: RecurringSeriesEntity,
        from item: RecurringSeries,
        accountDict: [String: AccountEntity],
        context: NSManagedObjectContext
    ) {
        // Caller is already inside context.perform — direct mutations are safe
        entity.isActive = item.isActive
        entity.amount = NSDecimalNumber(decimal: item.amount)
        entity.currency = item.currency
        entity.category = item.category
        entity.subcategory = item.subcategory
        entity.descriptionText = item.description
        entity.frequency = item.frequency.rawValue
        entity.startDate = DateFormatters.dateFormatter.date(from: item.startDate)
        entity.lastGeneratedDate = item.lastGeneratedDate.flatMap { DateFormatters.dateFormatter.date(from: $0) }
        entity.kind = item.kind.rawValue

        // Save iconSource as brandLogo/brandId strings (backward compatible)
        if let iconSource = item.iconSource {
            switch iconSource {
            case .bankLogo(let bankLogo):
                entity.brandLogo = bankLogo.rawValue
                entity.brandId = nil
            case .brandService(let brandId):
                entity.brandLogo = nil
                entity.brandId = brandId
            case .sfSymbol:
                entity.brandLogo = nil
                entity.brandId = nil
            }
        } else {
            entity.brandLogo = nil
            entity.brandId = nil
        }
        entity.status = item.status?.rawValue

        // Update account relationship using pre-fetched dictionary (O(1) lookup)
        entity.account = accountDict[item.accountId ?? ""]
    }

    private nonisolated func fetchRecurringSeriesSync(id: String, context: NSManagedObjectContext) -> RecurringSeriesEntity? {
        let request = NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }
}
