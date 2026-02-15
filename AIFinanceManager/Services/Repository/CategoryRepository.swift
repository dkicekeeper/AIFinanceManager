//
//  CategoryRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Category-specific data persistence operations

import Foundation
import CoreData

/// Protocol for category repository operations
protocol CategoryRepositoryProtocol {
    func loadCategories() -> [CustomCategory]
    func saveCategories(_ categories: [CustomCategory])
    func saveCategoriesSync(_ categories: [CustomCategory]) throws
    func loadCategoryRules() -> [CategoryRule]
    func saveCategoryRules(_ rules: [CategoryRule])
    func loadSubcategories() -> [Subcategory]
    func saveSubcategories(_ subcategories: [Subcategory])
    func saveSubcategoriesSync(_ subcategories: [Subcategory]) throws
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink]
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink])
    func saveCategorySubcategoryLinksSync(_ links: [CategorySubcategoryLink]) throws
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink]
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink])
    func saveTransactionSubcategoryLinksSync(_ links: [TransactionSubcategoryLink]) throws
    func loadAggregates(year: Int16?, month: Int16?, limit: Int?) -> [CategoryAggregate]
    func saveAggregates(_ aggregates: [CategoryAggregate])
}

/// CoreData implementation of CategoryRepositoryProtocol
final class CategoryRepository: CategoryRepositoryProtocol {

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

    // MARK: - Categories

    func loadCategories() -> [CustomCategory] {
        PerformanceProfiler.start("CategoryRepository.loadCategories")

        let context = stack.viewContext
        let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let entities = try context.fetch(request)
            let categories = entities.map { $0.toCustomCategory() }

            PerformanceProfiler.end("CategoryRepository.loadCategories")

            return categories
        } catch {
            PerformanceProfiler.end("CategoryRepository.loadCategories")

            // Fallback to UserDefaults if Core Data fails
            return userDefaultsRepository.loadCategories()
        }
    }

    func saveCategories(_ categories: [CustomCategory]) {

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("CategoryRepository.saveCategories")

            do {
                try await self.saveCoordinator.performSave(operation: "saveCategories") { context in
                    try self.saveCategoriesInternal(categories, context: context)
                }

                PerformanceProfiler.end("CategoryRepository.saveCategories")

            } catch {
                PerformanceProfiler.end("CategoryRepository.saveCategories")
            }
        }
    }

    func saveCategoriesSync(_ categories: [CustomCategory]) throws {
        let context = stack.viewContext
        try saveCategoriesInternal(categories, context: context)

        // Save if there are changes
        if context.hasChanges {
            try context.save()
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
                    try self.saveSubcategoriesInternal(subcategories, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                }
            }
        }
    }

    func saveSubcategoriesSync(_ subcategories: [Subcategory]) throws {
        PerformanceProfiler.start("CategoryRepository.saveSubcategoriesSync")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveSubcategoriesInternal(subcategories, context: backgroundContext)

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveSubcategoriesSync")
    }

    // MARK: - Category-Subcategory Links

    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        let context = stack.viewContext
        let request = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "categoryId", ascending: true)]

        do {
            let entities = try context.fetch(request)
            let links = entities.map { $0.toCategorySubcategoryLink() }
            print("📥 [CategoryRepository] Loaded \(links.count) category-subcategory links from Core Data")
            return links
        } catch {
            print("❌ [CategoryRepository] Failed to load category-subcategory links: \(error.localizedDescription)")
            print("⚠️ [CategoryRepository] Falling back to UserDefaults")
            return userDefaultsRepository.loadCategorySubcategoryLinks()
        }
    }

    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {

        Task.detached(priority: .utility) { @MainActor [weak self] in
            guard let self = self else { return }

            let context = self.stack.newBackgroundContext()

            await context.perform {
                do {
                    try self.saveCategorySubcategoryLinksInternal(links, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                }
            }
        }
    }

    func saveCategorySubcategoryLinksSync(_ links: [CategorySubcategoryLink]) throws {
        PerformanceProfiler.start("CategoryRepository.saveCategorySubcategoryLinksSync")

        print("💾 [CategoryRepository] Saving \(links.count) category-subcategory links...")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveCategorySubcategoryLinksInternal(links, context: backgroundContext)

            var createdCount = 0
            var updatedCount = 0
            // Counts already calculated in internal method

            print("💾 [CategoryRepository] Link sync operation completed")

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
                print("✅ [CategoryRepository] Saved \(links.count) category-subcategory links to Core Data")
            } else {
                print("⚠️ [CategoryRepository] No changes to save for category-subcategory links")
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveCategorySubcategoryLinksSync")
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
                    try self.saveTransactionSubcategoryLinksInternal(links, context: context)

                    // Save if there are changes
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                }
            }
        }
    }

    func saveTransactionSubcategoryLinksSync(_ links: [TransactionSubcategoryLink]) throws {
        PerformanceProfiler.start("CategoryRepository.saveTransactionSubcategoryLinksSync")

        // Use background context to avoid blocking UI
        let backgroundContext = stack.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try backgroundContext.performAndWait {
            try saveTransactionSubcategoryLinksInternal(links, context: backgroundContext)

            // Save if there are changes
            if backgroundContext.hasChanges {
                try backgroundContext.save()
            }
        }

        PerformanceProfiler.end("CategoryRepository.saveTransactionSubcategoryLinksSync")
    }

    // MARK: - Category Aggregates

    func loadAggregates(
        year: Int16? = nil,
        month: Int16? = nil,
        limit: Int? = nil
    ) -> [CategoryAggregate] {
        let context = stack.viewContext
        let request = CategoryAggregateEntity.fetchRequest()

        // Build predicates for filtering
        var predicates: [NSPredicate] = []

        if let year = year {
            let yearPredicate = NSPredicate(format: "year == %d OR year == 0", year)
            predicates.append(yearPredicate)

            if let month = month {
                let monthPredicate = NSPredicate(format: "month == %d OR month == 0", month)
                predicates.append(monthPredicate)
            }
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "lastUpdated", ascending: false)
        ]

        if let limit = limit {
            request.fetchLimit = limit
        }

        do {
            let entities = try context.fetch(request)
            return entities.map { $0.toAggregate() }
        } catch {
            return []
        }
    }

    func saveAggregates(_ aggregates: [CategoryAggregate]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.saveCoordinator.performSave(operation: "saveAggregates") { context in
                    try self.saveAggregatesInternal(aggregates, context: context)
                }
            } catch {
                // Логировать ошибку
            }
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func saveCategoriesInternal(_ categories: [CustomCategory], context: NSManagedObjectContext) throws {
        // Fetch all existing categories
        let fetchRequest = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely, handling duplicates
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
                if case .sfSymbol(let symbolName) = category.iconSource {
                    existing.iconName = symbolName
                } else {
                    existing.iconName = "questionmark.circle"
                }
                existing.colorHex = category.colorHex
                existing.budgetAmount = category.budgetAmount ?? 0.0
                existing.budgetPeriod = category.budgetPeriod.rawValue
                existing.budgetStartDate = category.budgetStartDate
                existing.budgetResetDay = Int64(category.budgetResetDay)
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

    private nonisolated func saveSubcategoriesInternal(_ subcategories: [Subcategory], context: NSManagedObjectContext) throws {
        // Fetch all existing subcategories
        let fetchRequest = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely
        var existingDict: [String: SubcategoryEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
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
    }

    private nonisolated func saveCategorySubcategoryLinksInternal(_ links: [CategorySubcategoryLink], context: NSManagedObjectContext) throws {
        // Fetch all existing links
        let fetchRequest = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely
        var existingDict: [String: CategorySubcategoryLinkEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
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
    }

    private nonisolated func saveTransactionSubcategoryLinksInternal(_ links: [TransactionSubcategoryLink], context: NSManagedObjectContext) throws {
        // Fetch all existing links
        let fetchRequest = NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely
        var existingDict: [String: TransactionSubcategoryLinkEntity] = [:]
        for entity in existingEntities {
            let id = entity.id ?? ""
            if !id.isEmpty && existingDict[id] == nil {
                existingDict[id] = entity
            } else if !id.isEmpty {
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
    }

    private nonisolated func saveAggregatesInternal(_ aggregates: [CategoryAggregate], context: NSManagedObjectContext) throws {
        // Fetch существующие агрегаты
        let fetchRequest = CategoryAggregateEntity.fetchRequest()
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: CategoryAggregateEntity] = [:]
        for entity in existingEntities {
            if let id = entity.id {
                existingDict[id] = entity
            }
        }

        var keptIds = Set<String>()

        // Обновить или создать агрегаты
        for aggregate in aggregates {
            keptIds.insert(aggregate.id)

            if let existing = existingDict[aggregate.id] {
                // Обновить существующий
                existing.categoryName = aggregate.categoryName
                existing.subcategoryName = aggregate.subcategoryName
                existing.year = aggregate.year
                existing.month = aggregate.month
                existing.totalAmount = aggregate.totalAmount
                existing.transactionCount = aggregate.transactionCount
                existing.currency = aggregate.currency
                existing.lastUpdated = Date()
                existing.lastTransactionDate = aggregate.lastTransactionDate
            } else {
                // Создать новый
                _ = CategoryAggregateEntity.from(aggregate, context: context)
            }
        }

        // Удалить агрегаты, которых больше нет
        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }
}
