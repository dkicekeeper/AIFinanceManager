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

/// Core Data Stack - Singleton for managing Core Data
class CoreDataStack {
    
    // MARK: - Singleton
    
    static let shared = CoreDataStack()
    
    private init() {
        print("🗄️ [CORE_DATA] Initializing CoreDataStack")
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
        print("🔔 [CORE_DATA] App will resign active - saving context")
        saveContextSync()
    }
    
    @objc private func saveOnTerminate() {
        print("🔔 [CORE_DATA] App will terminate - saving context")
        saveContextSync()
    }
    
    private func saveContextSync() {
        let context = viewContext
        guard context.hasChanges else {
            print("⏭️ [CORE_DATA] No changes to save")
            return
        }
        
        do {
            try context.save()
            print("✅ [CORE_DATA] Context saved successfully on app lifecycle event")
        } catch {
            let nsError = error as NSError
            print("❌ [CORE_DATA] Error saving context: \(nsError), \(nsError.userInfo)")
        }
    }
    
    // MARK: - Persistent Container
    
    lazy var persistentContainer: NSPersistentContainer = {
        print("🗄️ [CORE_DATA] Creating NSPersistentContainer")
        let container = NSPersistentContainer(name: "AIFinanceManager")
        
        // Configure container
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this error appropriately
                fatalError("❌ [CORE_DATA] Unresolved error \(error), \(error.userInfo)")
            }
            print("✅ [CORE_DATA] Persistent store loaded: \(storeDescription)")
        }
        
        // Automatic merge from parent context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Undo manager for view context (optional, can be disabled for performance)
        container.viewContext.undoManager = nil
        
        print("✅ [CORE_DATA] CoreDataStack initialized")
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
        guard context.hasChanges else {
            print("⏭️ [CORE_DATA] No changes to save")
            return
        }
        
        context.perform {
            do {
                try context.save()
                print("✅ [CORE_DATA] Context saved successfully")
            } catch {
                let nsError = error as NSError
                print("❌ [CORE_DATA] Error saving context: \(nsError), \(nsError.userInfo)")
                
                // In production, handle this appropriately
                // For now, just print the error
            }
        }
    }
    
    /// Save context synchronously (use carefully, can block thread)
    /// - Parameter context: The context to save
    func saveContextSync(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else {
            print("⏭️ [CORE_DATA] No changes to save")
            return
        }
        
        try context.save()
        print("✅ [CORE_DATA] Context saved synchronously")
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
        
        print("✅ [CORE_DATA] Batch deleted \(objectIDArray.count) objects")
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
        
        print("✅ [CORE_DATA] Batch updated \(objectIDArray.count) objects")
    }
    
    // MARK: - Reset
    
    /// Delete all data from persistent store (use for testing/debugging)
    func resetAllData() throws {
        print("⚠️ [CORE_DATA] Resetting all data")
        
        let coordinator = persistentContainer.persistentStoreCoordinator
        
        for store in coordinator.persistentStores {
            if let storeURL = store.url {
                try coordinator.destroyPersistentStore(at: storeURL, ofType: store.type, options: nil)
                try coordinator.addPersistentStore(ofType: store.type, configurationName: nil, at: storeURL, options: nil)
            }
        }
        
        print("✅ [CORE_DATA] All data reset")
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
            print("❌ [CORE_DATA] Error getting store size: \(error)")
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
                print("❌ [CORE_DATA] Error in performAndSave: \(error)")
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
