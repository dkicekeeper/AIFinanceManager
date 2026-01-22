//
//  UserDefaultsRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  UserDefaults implementation of DataRepositoryProtocol

import Foundation

/// UserDefaults-based implementation of DataRepositoryProtocol
/// Handles all data persistence operations using UserDefaults
nonisolated final class UserDefaultsRepository: DataRepositoryProtocol {
    
    // MARK: - Storage Keys
    
    private let storageKeyTransactions = "allTransactions"
    private let storageKeyRules = "categoryRules"
    private let storageKeyAccounts = "accounts"
    private let storageKeyCustomCategories = "customCategories"
    private let storageKeyRecurringSeries = "recurringSeries"
    private let storageKeyRecurringOccurrences = "recurringOccurrences"
    private let storageKeySubcategories = "subcategories"
    private let storageKeyCategorySubcategoryLinks = "categorySubcategoryLinks"
    private let storageKeyTransactionSubcategoryLinks = "transactionSubcategoryLinks"
    
    // MARK: - UserDefaults
    
    private let userDefaults: UserDefaults
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Transactions
    
    func loadTransactions() -> [Transaction] {
        guard let data = userDefaults.data(forKey: storageKeyTransactions),
              let decoded = try? JSONDecoder().decode([Transaction].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveTransactions(_ transactions: [Transaction]) {
        // Perform save asynchronously on background queue
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveTransactions")
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(transactions) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyTransactions)
            }
            
            PerformanceProfiler.end("saveTransactions")
        }
    }
    
    // MARK: - Accounts
    
    func loadAccounts() -> [Account] {
        guard let data = userDefaults.data(forKey: storageKeyAccounts),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveAccounts(_ accounts: [Account]) {
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveAccounts")
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(accounts) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyAccounts)
            }
            
            PerformanceProfiler.end("saveAccounts")
        }
    }
    
    // MARK: - Categories
    
    func loadCategories() -> [CustomCategory] {
        guard let data = userDefaults.data(forKey: storageKeyCustomCategories),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            print("🔴 UserDefaultsRepository.loadCategories() - NO DATA or DECODE FAILED")
            return []
        }
        print("🟢 UserDefaultsRepository.loadCategories() - Loaded \(decoded.count) categories")
        print("🟢 UserDefaultsRepository.loadCategories() - First 5 categories: \(decoded.prefix(5).map { "\($0.name): \($0.id)" })")
        return decoded
    }
    
    func saveCategories(_ categories: [CustomCategory]) {
        print("🔶 UserDefaultsRepository.saveCategories() - ASYNC save started for \(categories.count) categories")
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(categories) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyCustomCategories)
                print("🔶 UserDefaultsRepository.saveCategories() - ASYNC save completed")
            } else {
                print("🔴 UserDefaultsRepository.saveCategories() - ASYNC save FAILED to encode")
            }
        }
    }
    
    // MARK: - Category Rules
    
    func loadCategoryRules() -> [CategoryRule] {
        guard let data = userDefaults.data(forKey: storageKeyRules),
              let decoded = try? JSONDecoder().decode([CategoryRule].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveCategoryRules(_ rules: [CategoryRule]) {
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveCategoryRules")
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(rules) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRules)
            }
            
            PerformanceProfiler.end("saveCategoryRules")
        }
    }
    
    // MARK: - Recurring Series
    
    func loadRecurringSeries() -> [RecurringSeries] {
        guard let data = userDefaults.data(forKey: storageKeyRecurringSeries),
              let decoded = try? JSONDecoder().decode([RecurringSeries].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveRecurringSeries(_ series: [RecurringSeries]) {
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveRecurringSeries")
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(series) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRecurringSeries)
            }
            
            PerformanceProfiler.end("saveRecurringSeries")
        }
    }
    
    // MARK: - Recurring Occurrences
    
    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        guard let data = userDefaults.data(forKey: storageKeyRecurringOccurrences),
              let decoded = try? JSONDecoder().decode([RecurringOccurrence].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {
        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveRecurringOccurrences")
            
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(occurrences) {
                UserDefaults.standard.set(encoded, forKey: self.storageKeyRecurringOccurrences)
            }
            
            PerformanceProfiler.end("saveRecurringOccurrences")
        }
    }
    
    // MARK: - Subcategories
    
    func loadSubcategories() -> [Subcategory] {
        guard let data = userDefaults.data(forKey: storageKeySubcategories),
              let decoded = try? JSONDecoder().decode([Subcategory].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveSubcategories(_ subcategories: [Subcategory]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(subcategories) {
            userDefaults.set(encoded, forKey: storageKeySubcategories)
            userDefaults.synchronize() // Гарантируем немедленное сохранение
        }
    }
    
    // MARK: - Category-Subcategory Links
    
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        guard let data = userDefaults.data(forKey: storageKeyCategorySubcategoryLinks),
              let decoded = try? JSONDecoder().decode([CategorySubcategoryLink].self, from: data) else {
            print("🔴 UserDefaultsRepository.loadCategorySubcategoryLinks() - NO DATA or DECODE FAILED")
            return []
        }
        print("🟣 UserDefaultsRepository.loadCategorySubcategoryLinks() - Loaded \(decoded.count) links from UserDefaults")
        return decoded
    }

    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        print("🟣 UserDefaultsRepository.saveCategorySubcategoryLinks() - Saving \(links.count) links to UserDefaults")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(links) {
            userDefaults.set(encoded, forKey: storageKeyCategorySubcategoryLinks)
            userDefaults.synchronize() // Гарантируем немедленное сохранение
            print("🟣 UserDefaultsRepository.saveCategorySubcategoryLinks() - SAVED successfully")
        } else {
            print("🔴 UserDefaultsRepository.saveCategorySubcategoryLinks() - ENCODE FAILED")
        }
    }
    
    // MARK: - Transaction-Subcategory Links
    
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        guard let data = userDefaults.data(forKey: storageKeyTransactionSubcategoryLinks),
              let decoded = try? JSONDecoder().decode([TransactionSubcategoryLink].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(links) {
            userDefaults.set(encoded, forKey: storageKeyTransactionSubcategoryLinks)
            userDefaults.synchronize() // Гарантируем немедленное сохранение
        }
    }
    
    // MARK: - Clear All Data
    
    /// Clears all stored data
    func clearAllData() {
        let keys = [
            storageKeyTransactions,
            storageKeyRules,
            storageKeyAccounts,
            storageKeyCustomCategories,
            storageKeyRecurringSeries,
            storageKeyRecurringOccurrences,
            storageKeySubcategories,
            storageKeyCategorySubcategoryLinks,
            storageKeyTransactionSubcategoryLinks
        ]
        
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
        
        userDefaults.synchronize()
    }
}
