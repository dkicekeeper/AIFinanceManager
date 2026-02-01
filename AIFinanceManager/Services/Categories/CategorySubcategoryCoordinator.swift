//
//  CategorySubcategoryCoordinator.swift
//  AIFinanceManager
//
//  Service for managing subcategories and their links to categories/transactions
//  Extracted from CategoriesViewModel for better separation of concerns
//

import Foundation

/// Service responsible for subcategory and link management
@MainActor
final class CategorySubcategoryCoordinator: CategorySubcategoryCoordinatorProtocol {

    // MARK: - Dependencies

    /// Delegate for callbacks to ViewModel
    weak var delegate: CategorySubcategoryDelegate?

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
    init(delegate: CategorySubcategoryDelegate, repository: DataRepositoryProtocol) {
        self.delegate = delegate
        self.repository = repository
    }

    // MARK: - Subcategory CRUD

    func addSubcategory(name: String) -> Subcategory {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - creating orphan subcategory")
            #endif
            return Subcategory(name: name)
        }

        let subcategory = Subcategory(name: name)
        delegate.subcategories.append(subcategory)
        repository.saveSubcategories(delegate.subcategories)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Added subcategory: \(name)")
        #endif

        return subcategory
    }

    func updateSubcategory(_ subcategory: Subcategory) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot update subcategory")
            #endif
            return
        }

        guard let index = delegate.subcategories.firstIndex(where: { $0.id == subcategory.id }) else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] Subcategory not found: \(subcategory.name)")
            #endif
            return
        }

        // Create new array to trigger @Published update
        var newSubcategories = delegate.subcategories
        newSubcategories[index] = subcategory

        delegate.subcategories = newSubcategories
        repository.saveSubcategories(delegate.subcategories)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Updated subcategory: \(subcategory.name)")
        #endif
    }

    func deleteSubcategory(_ subcategoryId: String) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot delete subcategory")
            #endif
            return
        }

        // Remove all links to this subcategory
        delegate.categorySubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        delegate.transactionSubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }

        // Remove the subcategory itself
        delegate.subcategories.removeAll { $0.id == subcategoryId }

        // Save all changes
        repository.saveSubcategories(delegate.subcategories)
        repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Deleted subcategory: \(subcategoryId)")
        #endif
    }

    func searchSubcategories(query: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }

        let queryLower = query.lowercased()
        return delegate.subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }

    // MARK: - Category-Subcategory Links

    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        linkSubcategoryToCategoryWithoutSaving(subcategoryId: subcategoryId, categoryId: categoryId)

        guard let delegate = delegate else { return }
        repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Linked subcategory \(subcategoryId) to category \(categoryId)")
        #endif
    }

    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot link subcategory to category")
            #endif
            return
        }

        // Check if link already exists
        let existingLink = delegate.categorySubcategoryLinks.first { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }

        guard existingLink == nil else {
            #if DEBUG
            print("ℹ️ [CategorySubcategoryCoordinator] Link already exists: \(subcategoryId) → \(categoryId)")
            #endif
            return
        }

        let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
        delegate.categorySubcategoryLinks.append(link)
    }

    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot unlink subcategory")
            #endif
            return
        }

        delegate.categorySubcategoryLinks.removeAll { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }

        repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Unlinked subcategory \(subcategoryId) from category \(categoryId)")
        #endif
    }

    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }

        let linkedSubcategoryIds = delegate.categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }

        return delegate.subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    // MARK: - Transaction-Subcategory Links

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        guard let delegate = delegate else { return [] }

        let linkedSubcategoryIds = delegate.transactionSubcategoryLinks
            .filter { $0.transactionId == transactionId }
            .map { $0.subcategoryId }

        return delegate.subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot link subcategories to transaction")
            #endif
            return
        }

        // Remove old links
        delegate.transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }

        // Add new links
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            delegate.transactionSubcategoryLinks.append(link)
        }

        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Linked \(subcategoryIds.count) subcategories to transaction \(transactionId)")
        #endif
    }

    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String]) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot link subcategories without saving")
            #endif
            return
        }

        // Remove old links
        delegate.transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }

        // Add new links
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            delegate.transactionSubcategoryLinks.append(link)
        }
        // Do not save - will be saved in batch
    }

    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]]) {
        guard var delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot batch link subcategories")
            #endif
            return
        }

        // Remove old links for all transactions in batch
        let transactionIds = Set(links.keys)
        delegate.transactionSubcategoryLinks.removeAll { transactionIds.contains($0.transactionId) }

        // Add new links
        for (transactionId, subcategoryIds) in links {
            for subcategoryId in subcategoryIds {
                let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
                delegate.transactionSubcategoryLinks.append(link)
            }
        }

        // Save once at the end
        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Batch linked subcategories for \(transactionIds.count) transactions")
        #endif
    }

    // MARK: - Batch Operations

    func saveTransactionSubcategoryLinks() {
        guard let delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot save transaction subcategory links")
            #endif
            return
        }

        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Saved transaction subcategory links")
        #endif
    }

    func saveAllData() {
        guard let delegate = delegate else {
            #if DEBUG
            print("⚠️ [CategorySubcategoryCoordinator] No delegate set - cannot save all data")
            #endif
            return
        }

        repository.saveSubcategories(delegate.subcategories)
        repository.saveCategorySubcategoryLinks(delegate.categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(delegate.transactionSubcategoryLinks)

        #if DEBUG
        print("✅ [CategorySubcategoryCoordinator] Saved all subcategory data")
        #endif
    }
}

// MARK: - Factory Methods

extension CategorySubcategoryCoordinator {
    /// Create coordinator with delegate
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - repository: Data repository
    /// - Returns: Configured coordinator
    static func create(
        delegate: CategorySubcategoryDelegate,
        repository: DataRepositoryProtocol
    ) -> CategorySubcategoryCoordinator {
        CategorySubcategoryCoordinator(delegate: delegate, repository: repository)
    }
}
