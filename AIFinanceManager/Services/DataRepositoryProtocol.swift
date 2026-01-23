//
//  DataRepositoryProtocol.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Protocol defining data persistence operations for all entities

import Foundation

/// Protocol for data repository operations
/// Provides abstraction layer for data persistence
protocol DataRepositoryProtocol {
    // MARK: - Transactions
    
    /// Load transactions with optional date range filter
    /// - Parameter dateRange: Optional date range to filter transactions. If nil, loads all transactions
    /// - Returns: Array of transactions matching the filter
    func loadTransactions(dateRange: DateInterval?) -> [Transaction]
    
    func saveTransactions(_ transactions: [Transaction])
    
    // MARK: - Accounts
    func loadAccounts() -> [Account]
    func saveAccounts(_ accounts: [Account])
    
    // MARK: - Categories
    func loadCategories() -> [CustomCategory]
    func saveCategories(_ categories: [CustomCategory])
    
    // MARK: - Category Rules
    func loadCategoryRules() -> [CategoryRule]
    func saveCategoryRules(_ rules: [CategoryRule])
    
    // MARK: - Recurring Series
    func loadRecurringSeries() -> [RecurringSeries]
    func saveRecurringSeries(_ series: [RecurringSeries])
    
    // MARK: - Recurring Occurrences
    func loadRecurringOccurrences() -> [RecurringOccurrence]
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])
    
    // MARK: - Subcategories
    func loadSubcategories() -> [Subcategory]
    func saveSubcategories(_ subcategories: [Subcategory])
    
    // MARK: - Category-Subcategory Links
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink]
    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink])
    
    // MARK: - Transaction-Subcategory Links
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink]
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink])
    
    // MARK: - Clear All Data
    func clearAllData()
}
