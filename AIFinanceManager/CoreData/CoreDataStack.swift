//
//  CoreDataStack.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Core Data Stack for managing persistent storage

import Foundation
import CoreData
import Combine
import UIKit
import os

/// Core Data Stack - Singleton for managing Core Data
final class CoreDataStack: @unchecked Sendable {

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CoreDataStack")

    // MARK: - Singleton

    nonisolated static let shared = CoreDataStack()

    /// Флаг доступности CoreData. При ошибке инициализации = false → приложение работает через UserDefaults fallback.
    private(set) var isCoreDataAvailable: Bool = true

    /// Ошибка инициализации CoreData (для отображения пользователю)
    private(set) var initializationError: String? = nil

    private init() {
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Save context when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveOnBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // Save context before app terminates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveOnTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func saveOnBackground() {
        saveContextSync()
    }

    @objc private func saveOnTerminate() {
        saveContextSync()
    }

    private func saveContextSync() {
        let context = viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            CoreDataStack.logger.error("Error saving context on lifecycle event: \(error as NSError)")
        }
    }
    
    // MARK: - Persistent Container
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AIFinanceManager")
        
        // Configure container
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Enable automatic lightweight migration
        description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        container.loadPersistentStores { [self] storeDescription, error in
            if let error = error as NSError? {
                CoreDataStack.logger.critical("Persistent store failed to load: \(error), \(error.userInfo)")
                self.isCoreDataAvailable = false
                if error.code == NSPersistentStoreIncompatibleVersionHashError ||
                   error.code == NSMigrationMissingSourceModelError {
                    self.initializationError = String(localized: "error.coredata.migrationFailed")
                } else {
                    self.initializationError = String(localized: "error.coredata.initializationFailed")
                }
            }
        }
        
        // Automatic merge from parent context
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Use constraint merge policy to handle unique constraint violations
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Undo manager for view context (optional, can be disabled for performance)
        container.viewContext.undoManager = nil
        
        return container
    }()
    
    // MARK: - Contexts
    
    /// Main view context - use for UI operations on main thread
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    /// Create new background context for heavy operations
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }
    
    // MARK: - Save Operations
    
    /// Save context if it has changes
    /// - Parameter context: The context to save
    func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }

        context.perform {
            do {
                try context.save()
            } catch {
                CoreDataStack.logger.error("Error saving context: \(error as NSError)")
            }
        }
    }
    
    /// Save context synchronously (use carefully, can block thread)
    /// - Parameter context: The context to save
    func saveContextSync(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
    
    // MARK: - Batch Operations
    
    /// Execute batch delete request
    /// - Parameter fetchRequest: The fetch request defining objects to delete
    func batchDelete<T: NSManagedObject>(_ fetchRequest: NSFetchRequest<T>) throws {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID] ?? []
        
        // Merge changes to view context
        let changes = [NSDeletedObjectsKey: objectIDArray]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
    }
    
    /// Execute batch update request
    /// - Parameter batchUpdate: The batch update request
    func batchUpdate(_ batchUpdate: NSBatchUpdateRequest) throws {
        batchUpdate.resultType = .updatedObjectIDsResultType

        let result = try viewContext.execute(batchUpdate) as? NSBatchUpdateResult
        let objectIDArray = result?.result as? [NSManagedObjectID] ?? []

        // Merge changes to view context
        let changes = [NSUpdatedObjectsKey: objectIDArray]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
    }

    /// Merge inserted object IDs from an NSBatchInsertRequest result into viewContext.
    /// Must be called after executing NSBatchInsertRequest to keep viewContext in sync.
    /// NSBatchInsertRequest writes directly to SQLite and bypasses the managed object
    /// lifecycle, so automaticallyMergesChangesFromParent does NOT propagate the changes.
    func mergeBatchInsertResult(_ result: NSBatchInsertResult?) {
        guard let objectIDs = result?.result as? [NSManagedObjectID],
              !objectIDs.isEmpty else { return }
        let changes = [NSInsertedObjectIDsKey: objectIDs]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
    }

    // MARK: - Persistent History

    /// Purge persistent history older than `days` days.
    /// Called once per launch from a background task to prevent unbounded DB growth.
    func purgeHistory(olderThan days: Int = 7) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return }
        let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
        // viewContext is main-thread affined — must use perform for thread safety.
        viewContext.perform {
            do {
                try self.viewContext.execute(purgeRequest)
                CoreDataStack.logger.info("Purged persistent history older than \(days) days")
            } catch {
                CoreDataStack.logger.error("Failed to purge persistent history: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reset

    /// Delete all data from persistent store (use for testing/debugging)
    func resetAllData() throws {
        let coordinator = persistentContainer.persistentStoreCoordinator

        for store in coordinator.persistentStores {
            if let storeURL = store.url {
                try coordinator.destroyPersistentStore(at: storeURL, ofType: store.type, options: nil)
                try coordinator.addPersistentStore(ofType: store.type, configurationName: nil, at: storeURL, options: nil)
            }
        }
    }
    
    // MARK: - Performance Monitoring
    
    /// Get persistent store file size
    var storeSize: String {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else {
            return "Unknown"
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            CoreDataStack.logger.error("Error getting store size: \(error)")
        }
        
        return "Unknown"
    }
}

// MARK: - Convenience Extensions

extension NSManagedObjectContext {
    
    /// Perform operation and save if successful
    func performAndSave(_ block: @escaping () throws -> Void) {
        perform {
            do {
                try block()
                if self.hasChanges {
                    try self.save()
                }
            } catch {
                Logger(subsystem: "AIFinanceManager", category: "CoreDataStack").error("Error in performAndSave: \(error)")
            }
        }
    }
    
    /// Perform operation synchronously and save if successful
    func performAndSaveSync(_ block: () throws -> Void) throws {
        try block()
        if hasChanges {
            try save()
        }
    }
}
