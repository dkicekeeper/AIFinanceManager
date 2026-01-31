//
//  CategoriesViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing categories, subcategories, and category rules

import Foundation
import SwiftUI
import Combine

@MainActor
class CategoriesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var customCategories: [CustomCategory] = []
    @Published var categoryRules: [CategoryRule] = []
    @Published var subcategories: [Subcategory] = []
    @Published var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    @Published var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Private Properties

    private let repository: DataRepositoryProtocol
    private var currencyService: TransactionCurrencyService?
    private var appSettings: AppSettings?

    /// Lazy budget service - created when needed with current dependencies
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
        self.customCategories = repository.loadCategories()
        self.categoryRules = repository.loadCategoryRules()
        self.subcategories = repository.loadSubcategories()
        self.categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        self.transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        print("🔄 [CategoriesViewModel] Loaded \(customCategories.count) categories from storage")
        print("🔄 [CategoriesViewModel] Category names: \(customCategories.map { $0.name })")
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        customCategories = repository.loadCategories()
        categoryRules = repository.loadCategoryRules()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()
    }
    
    // MARK: - Category CRUD Operations
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        
        // Use synchronous save for user-initiated actions to prevent data loss
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(customCategories)
            } catch {
                // Keep async as fallback
                repository.saveCategories(customCategories)
            }
        } else {
            repository.saveCategories(customCategories)
        }
    }
    
    func updateCategory(_ category: CustomCategory) {
        guard let index = customCategories.firstIndex(where: { $0.id == category.id }) else {
            // Если категория не найдена, возможно это новая категория с существующим id
            // В этом случае добавляем её
            customCategories.append(category)
            saveCategories()
            return
        }

        // Создаем новый массив вместо модификации элемента на месте
        var newCategories = customCategories
        newCategories[index] = category

        // Переприсваиваем весь массив для триггера @Published
        customCategories = newCategories
        // NOTE: @Published automatically sends objectWillChange notification

        saveCategories()
    }
    
    func deleteCategory(_ category: CustomCategory, deleteTransactions: Bool = false) {
        // Note: deleteTransactions logic should be handled by TransactionsViewModel
        // This method only handles category deletion

        print("🗑️ [CategoriesViewModel] Deleting category '\(category.name)' - customCategories count BEFORE: \(customCategories.count)")

        // Удаляем категорию
        customCategories.removeAll { $0.id == category.id }

        print("🗑️ [CategoriesViewModel] Deleted category '\(category.name)' - customCategories count AFTER: \(customCategories.count)")

        saveCategories()

        print("🗑️ [CategoriesViewModel] Categories saved to storage")
    }
    
    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
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
            // Создаем новый массив вместо модификации элемента на месте
            var newRules = categoryRules
            newRules[index] = rule

            // Переприсваиваем весь массив для триггера @Published
            categoryRules = newRules
            // NOTE: @Published automatically sends objectWillChange notification

            repository.saveCategoryRules(categoryRules)
        }
    }
    
    func deleteRule(_ rule: CategoryRule) {
        categoryRules.removeAll { $0.description.lowercased() == rule.description.lowercased() }
        repository.saveCategoryRules(categoryRules)
    }
    
    // MARK: - Subcategory CRUD Operations
    
    func addSubcategory(name: String) -> Subcategory {
        let subcategory = Subcategory(name: name)
        subcategories.append(subcategory)
        repository.saveSubcategories(subcategories)
        return subcategory
    }
    
    func updateSubcategory(_ subcategory: Subcategory) {
        if let index = subcategories.firstIndex(where: { $0.id == subcategory.id }) {
            // Создаем новый массив вместо модификации элемента на месте
            var newSubcategories = subcategories
            newSubcategories[index] = subcategory

            // Переприсваиваем весь массив для триггера @Published
            subcategories = newSubcategories
            // NOTE: @Published automatically sends objectWillChange notification

            repository.saveSubcategories(subcategories)
        }
    }
    
    func deleteSubcategory(_ subcategoryId: String) {
        // Удаляем связи с категориями
        categorySubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        // Удаляем связи с транзакциями (оставляем транзакции, но убираем линк)
        transactionSubcategoryLinks.removeAll { $0.subcategoryId == subcategoryId }
        // Удаляем подкатегорию
        subcategories.removeAll { $0.id == subcategoryId }
        repository.saveSubcategories(subcategories)
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
    }
    
    // MARK: - Category-Subcategory Links
    
    func linkSubcategoryToCategory(subcategoryId: String, categoryId: String) {
        linkSubcategoryToCategoryWithoutSaving(subcategoryId: subcategoryId, categoryId: categoryId)
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
    }
    
    /// Связывает подкатегорию с категорией без немедленного сохранения (для массового импорта)
    func linkSubcategoryToCategoryWithoutSaving(subcategoryId: String, categoryId: String) {
        // Проверяем, нет ли уже такой связи
        let existingLink = categorySubcategoryLinks.first { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        
        if existingLink == nil {
            let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
            categorySubcategoryLinks.append(link)
        }
    }
    
    func unlinkSubcategoryFromCategory(subcategoryId: String, categoryId: String) {
        categorySubcategoryLinks.removeAll { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
    }
    
    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        let linkedSubcategoryIds = categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }

        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }
    
    // MARK: - Transaction-Subcategory Links
    
    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = transactionSubcategoryLinks
            .filter { $0.transactionId == transactionId }
            .map { $0.subcategoryId }
        
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }
    
    func linkSubcategoriesToTransaction(transactionId: String, subcategoryIds: [String]) {
        // Удаляем старые связи
        transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }
        
        // Добавляем новые связи
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            transactionSubcategoryLinks.append(link)
        }
        
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
    }
    
    /// Связывает подкатегории с транзакцией без немедленного сохранения (для массового импорта)
    func linkSubcategoriesToTransactionWithoutSaving(transactionId: String, subcategoryIds: [String]) {
        // Удаляем старые связи
        transactionSubcategoryLinks.removeAll { $0.transactionId == transactionId }
        
        // Добавляем новые связи
        for subcategoryId in subcategoryIds {
            let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
            transactionSubcategoryLinks.append(link)
        }
        // НЕ сохраняем - сохранение будет выполнено в конце импорта
    }
    
    /// Массовое связывание подкатегорий с транзакциями (для импорта)
    /// - Parameter links: Словарь [transactionId: [subcategoryIds]]
    func batchLinkSubcategoriesToTransaction(_ links: [String: [String]]) {
        // Удаляем старые связи для всех транзакций
        let transactionIds = Set(links.keys)
        transactionSubcategoryLinks.removeAll { transactionIds.contains($0.transactionId) }
        
        // Добавляем новые связи
        for (transactionId, subcategoryIds) in links {
            for subcategoryId in subcategoryIds {
                let link = TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId)
                transactionSubcategoryLinks.append(link)
            }
        }
        
        // Сохраняем один раз в конце
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
    }
    
    /// Принудительно сохраняет связи транзакций с подкатегориями (для использования после массового импорта)
    func saveTransactionSubcategoryLinks() {
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
    }
    
    func searchSubcategories(query: String) -> [Subcategory] {
        let queryLower = query.lowercased()
        return subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }
    
    /// Сохраняет все данные CategoriesViewModel (используется после массового импорта)
    func saveAllData() {
        repository.saveSubcategories(subcategories)
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)

        // ВАЖНО: saveCategories использует Task.detached, но для импорта
        // нам нужно синхронное сохранение. Поэтому сохраняем категории напрямую.
        saveCategoriesSync(customCategories)
    }

    /// Синхронно сохраняет категории (используется для импорта)
    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(categories)
            } catch {
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            repository.saveCategories(categories)
        }
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
    
    /// Save categories synchronously to prevent data loss on app termination
    private func saveCategories() {
        if let coreDataRepo = repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(customCategories)
            } catch {
                // Fallback to async save
                repository.saveCategories(customCategories)
            }
        } else {
            repository.saveCategories(customCategories)
        }
    }
}
