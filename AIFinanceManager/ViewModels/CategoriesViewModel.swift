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
    
    // MARK: - Initialization
    
    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        self.customCategories = repository.loadCategories()
        self.categoryRules = repository.loadCategoryRules()
        self.subcategories = repository.loadSubcategories()
        self.categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        self.transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        print("🟢 CategoriesViewModel.init() - Loaded \(subcategories.count) subcategories")
        print("🟢 CategoriesViewModel.init() - Loaded \(categorySubcategoryLinks.count) category-subcategory links")
        print("🟢 CategoriesViewModel.init() - Links: \(categorySubcategoryLinks.map { "cat:\($0.categoryId) -> sub:\($0.subcategoryId)" }.joined(separator: ", "))")
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
        print("🟡 CategoriesViewModel.reloadFromStorage() - BEFORE: \(categorySubcategoryLinks.count) links")

        customCategories = repository.loadCategories()
        categoryRules = repository.loadCategoryRules()
        subcategories = repository.loadSubcategories()
        categorySubcategoryLinks = repository.loadCategorySubcategoryLinks()
        transactionSubcategoryLinks = repository.loadTransactionSubcategoryLinks()

        print("🟡 CategoriesViewModel.reloadFromStorage() - AFTER: \(categorySubcategoryLinks.count) links")
        print("🟡 CategoriesViewModel.reloadFromStorage() - Links: \(categorySubcategoryLinks.map { "cat:\($0.categoryId) -> sub:\($0.subcategoryId)" }.joined(separator: ", "))")
    }
    
    // MARK: - Category CRUD Operations
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        print("⚠️ CategoriesViewModel.addCategory() - Calling repository.saveCategories (ASYNC)")
        repository.saveCategories(customCategories)
    }
    
    func updateCategory(_ category: CustomCategory) {
        guard let index = customCategories.firstIndex(where: { $0.id == category.id }) else {
            // Если категория не найдена, возможно это новая категория с существующим id
            // В этом случае добавляем её
            print("Warning: Category with id \(category.id) not found, adding as new")
            customCategories.append(category)
            print("⚠️ CategoriesViewModel.updateCategory() - Calling repository.saveCategories (ASYNC) - category not found case")
            repository.saveCategories(customCategories)
            return
        }
        customCategories[index] = category
        print("⚠️ CategoriesViewModel.updateCategory() - Calling repository.saveCategories (ASYNC)")
        repository.saveCategories(customCategories)
    }
    
    func deleteCategory(_ category: CustomCategory, deleteTransactions: Bool = false) {
        // Note: deleteTransactions logic should be handled by TransactionsViewModel
        // This method only handles category deletion
        
        // Удаляем категорию
        customCategories.removeAll { $0.id == category.id }
        repository.saveCategories(customCategories)
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
            categoryRules[index] = rule
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
            subcategories[index] = subcategory
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
        // Сохраняем сразу для обычных операций (не массовый импорт)
        print("🟠 CategoriesViewModel.linkSubcategoryToCategory() - Saving \(categorySubcategoryLinks.count) links")
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
        print("🟠 CategoriesViewModel.unlinkSubcategoryFromCategory() - Saving \(categorySubcategoryLinks.count) links")
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
    }
    
    func getSubcategoriesForCategory(_ categoryId: String) -> [Subcategory] {
        print("🔍 getSubcategoriesForCategory(\(categoryId))")
        print("🔍 Total categorySubcategoryLinks: \(categorySubcategoryLinks.count)")
        print("🔍 Total subcategories: \(subcategories.count)")

        // Показываем первые 5 category IDs из связей для отладки
        let sampleCategoryIds = Array(Set(categorySubcategoryLinks.map { $0.categoryId })).prefix(5)
        print("🔍 Sample category IDs in links: \(sampleCategoryIds)")

        // Показываем первые 5 category IDs из текущих категорий
        let currentCategoryIds = customCategories.prefix(5).map { "\($0.name): \($0.id)" }
        print("🔍 Current categories: \(currentCategoryIds)")

        let linkedSubcategoryIds = categorySubcategoryLinks
            .filter { $0.categoryId == categoryId }
            .map { $0.subcategoryId }

        print("🔍 Found \(linkedSubcategoryIds.count) linked subcategory IDs for category \(categoryId)")
        print("🔍 Linked IDs: \(linkedSubcategoryIds)")

        let result = subcategories.filter { linkedSubcategoryIds.contains($0.id) }
        print("🔍 Returning \(result.count) subcategories: \(result.map { $0.name })")

        return result
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
        // Сохраняем в правильном порядке: сначала подкатегории, потом связи
        // Все сохранения должны быть синхронными, чтобы гарантировать
        // что данные сохранены до того, как будет вызван reloadFromStorage()

        print("🔵 CategoriesViewModel.saveAllData() - Saving \(subcategories.count) subcategories")
        print("🔵 CategoriesViewModel.saveAllData() - Saving \(categorySubcategoryLinks.count) category-subcategory links")
        print("🔵 CategoriesViewModel.saveAllData() - Links: \(categorySubcategoryLinks.map { "cat:\($0.categoryId) -> sub:\($0.subcategoryId)" }.joined(separator: ", "))")

        repository.saveSubcategories(subcategories)
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)

        // ВАЖНО: saveCategories использует Task.detached, но для импорта
        // нам нужно синхронное сохранение. Поэтому сохраняем категории напрямую.
        saveCategoriesSync(customCategories)

        print("🔵 CategoriesViewModel.saveAllData() - COMPLETED")

        // ПРОВЕРКА: Читаем связи обратно из UserDefaults для проверки
        let savedLinks = repository.loadCategorySubcategoryLinks()
        print("✅ VERIFICATION: Just saved \(categorySubcategoryLinks.count) links, loaded back \(savedLinks.count) links from UserDefaults")
        if savedLinks.count != categorySubcategoryLinks.count {
            print("❌ ERROR: Mismatch! Expected \(categorySubcategoryLinks.count) but got \(savedLinks.count)")
        }
    }

    /// Синхронно сохраняет категории (используется для импорта)
    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(categories) {
            UserDefaults.standard.set(encoded, forKey: "customCategories")
            UserDefaults.standard.synchronize()
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
        // Only expense categories can have budgets
        guard let budgetAmount = category.budgetAmount,
              category.type == .expense else { return nil }

        // Calculate spent amount for current period
        let spent = calculateSpent(for: category, transactions: transactions)

        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    private func calculateSpent(for category: CustomCategory, transactions: [Transaction]) -> Double {
        let periodStart = budgetPeriodStart(for: category)
        let periodEnd = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return transactions
            .filter { transaction in
                guard transaction.category == category.name,
                      transaction.type == .expense,
                      let transactionDate = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return transactionDate >= periodStart && transactionDate <= periodEnd
            }
            .reduce(0) { $0 + $1.amount }
    }

    private func budgetPeriodStart(for category: CustomCategory) -> Date {
        guard category.budgetStartDate != nil else { return Date() }

        let calendar = Calendar.current
        let now = Date()

        switch category.budgetPeriod {
        case .weekly:
            // Start of current week
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            // Reset on specific day of month
            let components = calendar.dateComponents([.year, .month], from: now)
            var startComponents = components
            startComponents.day = category.budgetResetDay

            if let resetDate = calendar.date(from: startComponents) {
                // If reset day hasn't happened this month yet, use previous month
                if resetDate > now {
                    return calendar.date(byAdding: .month, value: -1, to: resetDate) ?? resetDate
                }
                return resetDate
            }
            return now
        case .yearly:
            // Start of current year
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
    }
}
