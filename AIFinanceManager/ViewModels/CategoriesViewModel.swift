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
    }
    
    // MARK: - Category CRUD Operations
    
    func addCategory(_ category: CustomCategory) {
        customCategories.append(category)
        repository.saveCategories(customCategories)
    }
    
    func updateCategory(_ category: CustomCategory) {
        guard let index = customCategories.firstIndex(where: { $0.id == category.id }) else {
            // Если категория не найдена, возможно это новая категория с существующим id
            // В этом случае добавляем её
            print("Warning: Category with id \(category.id) not found, adding as new")
            customCategories.append(category)
            repository.saveCategories(customCategories)
            return
        }
        customCategories[index] = category
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
        // Проверяем, нет ли уже такой связи
        let existingLink = categorySubcategoryLinks.first { link in
            link.categoryId == categoryId && link.subcategoryId == subcategoryId
        }
        
        if existingLink == nil {
            let link = CategorySubcategoryLink(categoryId: categoryId, subcategoryId: subcategoryId)
            categorySubcategoryLinks.append(link)
            repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)
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
    
    func searchSubcategories(query: String) -> [Subcategory] {
        let queryLower = query.lowercased()
        return subcategories.filter { $0.name.lowercased().contains(queryLower) }
    }
}
