//
//  CategoryCRUDService.swift
//  AIFinanceManager
//
//  Service for category CRUD operations
//  Extracted from CategoriesViewModel for better separation of concerns
//

import Foundation

/// Service responsible for category CRUD operations
@MainActor
final class CategoryCRUDService: CategoryCRUDServiceProtocol {

    // MARK: - Dependencies

    /// Delegate for callbacks to ViewModel
    weak var delegate: CategoryCRUDDelegate?

    /// Repository for persistence
    private let repository: DataRepositoryProtocol

    // MARK: - Initialization

    /// Initialize with repository
    /// - Parameter repository: Data repository for persistence
    init(repository: DataRepositoryProtocol) {
        self.repository = repository
    }

    /// Convenience initializer with delegate
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - repository: Data repository for persistence
    init(delegate: CategoryCRUDDelegate, repository: DataRepositoryProtocol) {
        self.delegate = delegate
        self.repository = repository
    }

    // MARK: - CategoryCRUDServiceProtocol Implementation

    func addCategory(_ category: CustomCategory) {
        guard let delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategoryCRUDService] No delegate set - cannot add category")
            #endif
            return
        }

        // Add to in-memory array
        var newCategories = delegate.customCategories
        newCategories.append(category)
        delegate.updateCategories(newCategories)

        // Persist synchronously to prevent data loss
        saveCategoriesSync(newCategories)

        #if DEBUG
        print("✅ [CategoryCRUDService] Added category: \(category.name)")
        #endif
    }

    func updateCategory(_ category: CustomCategory) {
        guard let delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategoryCRUDService] No delegate set - cannot update category")
            #endif
            return
        }

        // Find category index
        var newCategories = delegate.customCategories
        guard let index = newCategories.firstIndex(where: { $0.id == category.id }) else {
            // Category not found - treat as new category
            #if DEBUG
            print("⚠️ [CategoryCRUDService] Category not found, adding as new: \(category.name)")
            #endif
            newCategories.append(category)
            delegate.updateCategories(newCategories)
            saveCategoriesSync(newCategories)
            return
        }

        // Create new array to trigger @Published update
        newCategories[index] = category

        // Update in-memory array
        delegate.updateCategories(newCategories)

        // Persist synchronously
        saveCategoriesSync(newCategories)

        #if DEBUG
        print("✅ [CategoryCRUDService] Updated category: \(category.name)")
        #endif
    }

    func deleteCategory(_ category: CustomCategory) {
        guard let delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategoryCRUDService] No delegate set - cannot delete category")
            #endif
            return
        }

        // Remove from in-memory array
        var newCategories = delegate.customCategories
        newCategories.removeAll { $0.id == category.id }
        delegate.updateCategories(newCategories)

        // Persist synchronously
        saveCategoriesSync(newCategories)

        #if DEBUG
        print("✅ [CategoryCRUDService] Deleted category: \(category.name)")
        #endif
    }

    // MARK: - Private Helpers

    /// Save categories synchronously to prevent data loss
    /// - Parameter categories: Categories to save
    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(categories)
            } catch {
                #if DEBUG
                print("❌ [CategoryCRUDService] Failed to save categories: \(error)")
                #endif
                // Fallback to async save
                repository.saveCategories(categories)
            }
        } else {
            // For non-CoreData repositories, use async save
            repository.saveCategories(categories)
        }
    }
}

// MARK: - Factory Methods

extension CategoryCRUDService {
    /// Create service with delegate
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - repository: Data repository
    /// - Returns: Configured service
    static func create(
        delegate: CategoryCRUDDelegate,
        repository: DataRepositoryProtocol
    ) -> CategoryCRUDService {
        CategoryCRUDService(delegate: delegate, repository: repository)
    }
}
