//
//  CategoriesViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing categories, subcategories, and category rules
//  REFACTORED: Now uses dedicated services for SRP compliance

import Foundation
import SwiftUI
import Combine

@MainActor
class CategoriesViewModel: ObservableObject {
    // MARK: - Published Properties

    /// PHASE 3: Categories are now observed from TransactionStore (Single Source of Truth)
    /// This is synced from TransactionStore - ViewModels no longer own the data
    @Published private(set) var customCategories: [CustomCategory] = []

    @Published var categoryRules: [CategoryRule] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    @Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Publishers

    /// Publisher for customCategories changes
    /// Other ViewModels can subscribe to this instead of duplicating data
    var categoriesPublisher: AnyPublisher<[CustomCategory], Never> {
        $customCategories.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let repository: DataRepositoryProtocol
    private var currencyService: TransactionCurrencyService?
    private var appSettings: AppSettings?

    /// PHASE 3: TransactionStore as Single Source of Truth for categories
    /// ViewModels observe this instead of owning data
    weak var transactionStore: TransactionStore?

    private var categoriesSubscription: AnyCancellable?

    // MARK: - Services (Lazy Initialization)

    /// CRUD service - handles category create/update/delete
    private lazy var crudService: CategoryCRUDServiceProtocol = {
        CategoryCRUDService(delegate: self, repository: repository)
    }()

    /// Subcategory coordinator - handles subcategory and link management
    private lazy var subcategoryCoordinator: CategorySubcategoryCoordinatorProtocol = {
        CategorySubcategoryCoordinator(delegate: self, repository: repository)
    }()

    /// Budget coordinator - handles budget calculations (NOT USED YET - for future)
    /// Note: Currently using old CategoryBudgetService for compatibility
    private lazy var budgetCoordinator: CategoryBudgetCoordinatorProtocol = {
        CategoryBudgetCoordinator(
            delegate: self,
            currencyService: currencyService,
            appSettings: appSettings
        )
    }()

    /// Budget service for category budget management
    /// NOTE: Could be migrated to budgetCoordinator in future for better separation of concerns
    private lazy var budgetService: CategoryBudgetService = {
        CategoryBudgetService(
            currencyService: currencyService,
            appSettings: appSettings
        )
    }()

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol = UserDefaultsRepository(),
        currencyService: TransactionCurrencyService? = nil,
        appSettings: AppSettings? = nil
    ) {
        self.repository = repository
        self.currencyService = currencyService
        self.appSettings = appSettings
        // PHASE 3: Don't load categories here anymore - will be synced from TransactionStore
        // self.customCategories = repository.loadCategories()
        self.categoryRules = repository.loadCategoryRules()
        self.subcategories = repository.loadSubcategories()
        self.categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        self.transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
    }

    /// PHASE 3: Setup subscription to TransactionStore.$categories
    /// Called by AppCoordinator after TransactionStore is initialized
    func setupTransactionStoreObserver() {
        guard let transactionStore = transactionStore else {
            #if DEBUG
            print("⚠️ [CategoriesVM] TransactionStore not set, cannot setup observer")
            #endif
            return
        }

        categoriesSubscription = transactionStore.$categories
            .sink { [weak self] updatedCategories in
                guard let self = self else { return }
                self.customCategories = updatedCategories

                #if DEBUG
                print("✅ [CategoriesVM] Received \(updatedCategories.count) categories from TransactionStore")
                #endif
            }

        #if DEBUG
        print("✅ [CategoriesVM] Setup TransactionStore observer")
        #endif
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        // PHASE 3: TransactionStore is the owner - it will reload and publish to observers
        // No need to reload categories here - they will be updated via subscription
        categoryRules = repository.loadCategoryRules()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
    }

    // MARK: - Public Methods for Mutation

    /// Internal method to update categories array (triggers publisher)
    /// - Parameter categories: New categories array
    func updateCategories(_ categories: [CustomCategory]) {
        customCategories = categories
    }

    // MARK: - Category CRUD Operations

    func addCategory(_ category: CustomCategory) {
        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.addCategory(category)
    }

    func updateCategory(_ category: CustomCategory) {
        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.updateCategory(category)
    }

    func deleteCategory(_ category: CustomCategory, deleteTransactions: Bool = false) {
        // Note: deleteTransactions logic should be handled by TransactionsViewModel
        // This method only handles category deletion
        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.deleteCategory(category.id)
    }

    // MARK: - Category Rules Operations

    func addRule(_ rule: CategoryRule) {
        // Проверяем, нет ли уже правила с таким описанием
        if !categoryRules.contains(where: { $0.description.lowercased() == rule.description.lowercased() }) {
            categoryRules.append(rule)
            repository.saveCategoryRules(categoryRules)
        }
    }

    func updateRule(_ rule: CategoryRule) {
        // CategoryRule не имеет id, поэтому ищем по description
        if let index = categoryRules.firstIndex(where: { $0.description.lowercased() == rule.description.lowercased() }) {
            var newRules = categoryRules
            newRules[index] = rule
            categoryRules = newRules
            repository.saveCategoryRules(categoryRules)
        }
    }

    func deleteRule(_ rule: CategoryRule) {
        categoryRules.removeAll { $0.description.lowercased() == rule.description.lowercased() }
        repository.saveCategoryRules(categoryRules)
    }

    // MARK: - Subcategory CRUD Operations

    func addSubcategory(name: String) -> Subcategory {
        return subcategoryCoordinator.addSubcategory(name: name)
    }

    func updateSubcategory(_ subcategory: Subcategory) {
        subcategoryCoordinator.updateSubcategory(subcategory)
    }

    func deleteSubcategory(_ subcategoryId: String) {
        subcategoryCoordinator.deleteSubcategory(subcategoryId)
    }

    func searchSubcategories(query: String) -> [Subcategory] {
        return subcategoryCoordinator.searchSubcategories(query: query)
    }

    // MARK: - Category-Subcategory Links

    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.linkSubcategoryToCategory(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.linkSubcategoryToCategoryWithoutSaving(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        subcategoryCoordinator.unlinkSubcategoryFromCategory(
            subcategoryId: subcategoryId,
            categoryId: categoryId
        )
    }

    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        return subcategoryCoordinator.getSubcategoriesForCategory(categoryId)
    }

    // MARK: - Transaction-Subcategory Links

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        return subcategoryCoordinator.getSubcategoriesForTransaction(transactionId)
    }

    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        subcategoryCoordinator.linkSubcategoriesToTransaction(
            transactionId: transactionId,
            subcategoryIds: subcategoryIds
        )
    }

    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String]) {
        subcategoryCoordinator.linkSubcategoriesToTransactionWithoutSaving(
            transactionId: transactionId,
            subcategoryIds: subcategoryIds
        )
    }

    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]]) {
        subcategoryCoordinator.batchLinkSubcategoriesToTransaction(links)
    }

    func saveTransactionSubcategoryLinks() {
        subcategoryCoordinator.saveTransactionSubcategoryLinks()
    }

    // MARK: - Batch Operations

    /// Сохраняет все данные CategoriesViewModel (используется после массового импорта)
    /// PHASE 3: Category persistence now handled by TransactionStore
    func saveAllData() {
        subcategoryCoordinator.saveAllData()

        // PHASE 3: Categories are saved by TransactionStore
        #if DEBUG
        print("⚠️ [CategoriesVM] saveAllData - category persistence now handled by TransactionStore")
        #endif
    }

    // MARK: - Budget Management

    func setBudget(
        for categoryId: String,
        amount: Double,
        period: CustomCategory.BudgetPeriod = .monthly,
        resetDay: Int = 1
    ) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryId }) else { return }

        var category = customCategories[index]
        category.budgetAmount = amount
        category.budgetPeriod = period
        category.budgetStartDate = Date()
        category.budgetResetDay = resetDay

        updateCategory(category)
    }

    func removeBudget(for categoryId: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryId }) else { return }

        var category = customCategories[index]
        category.budgetAmount = nil
        category.budgetStartDate = nil

        updateCategory(category)
    }

    func budgetProgress(for category: CustomCategory, transactions: [Transaction]) -> BudgetProgress? {
        return budgetService.budgetProgress(for: category, transactions: transactions)
    }

    // MARK: - Private Helpers

    /// Schedule save operation (called by delegate)
    func scheduleSave() {
        // Implement debounced save if needed
        // For now, services handle saves directly
    }
}

// MARK: - CategoryCRUDDelegate

extension CategoriesViewModel: CategoryCRUDDelegate {
    // customCategories already declared as @Published property
    // scheduleSave already implemented above
}

// MARK: - CategorySubcategoryDelegate

extension CategoriesViewModel: CategorySubcategoryDelegate {
    // subcategories, categorySubcategoryLinks, transactionSubcategoryLinks
    // already declared as @Published properties
}

// MARK: - CategoryBudgetDelegate

extension CategoriesViewModel: CategoryBudgetDelegate {
    // customCategories already available
    // updateCategory already implemented
}
