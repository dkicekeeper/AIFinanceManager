//
//  EntityMappingServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for entity (account, category, subcategory) resolution during CSV import
/// Handles lookups, cache management, and entity creation
@MainActor
protocol EntityMappingServiceProtocol {
    /// Resolves an account by name, checking cache, mapping, and existing accounts
    /// Creates a new account if needed
    /// - Parameters:
    ///   - name: Account name from CSV
    ///   - currency: Account currency
    ///   - mapping: Entity mapping configuration
    ///   - accountsViewModel: Accounts view model for lookups and creation
    /// - Returns: Resolution result indicating if account was found or created
    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping,
        accountsViewModel: AccountsViewModel?
    ) async -> AccountResolutionResult

    /// Resolves a category by name, checking cache, mapping, and existing categories
    /// Creates a new category if needed
    /// - Parameters:
    ///   - name: Category name from CSV
    ///   - type: Transaction type for category
    ///   - mapping: Entity mapping configuration
    ///   - categoriesViewModel: Categories view model for lookups and creation
    /// - Returns: Resolution result indicating if category was found or created
    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult

    /// Resolves multiple subcategories, checking cache and existing subcategories
    /// Creates new subcategories if needed and links them to the category
    /// - Parameters:
    ///   - names: Array of subcategory names from CSV
    ///   - categoryId: Parent category ID for linking
    ///   - categoriesViewModel: Categories view model for lookups and creation
    /// - Returns: Array of resolution results for each subcategory
    func resolveSubcategories(
        names: [String],
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> [SubcategoryResolutionResult]
}

// MARK: - Resolution Result Types

/// Result of account resolution operation
enum AccountResolutionResult {
    /// Account already exists, returns ID
    case existing(id: String)
    /// Account was created, returns new ID
    case created(id: String)
    /// Account resolution was skipped (reserved name or empty)
    case skipped
}

/// Result of category resolution operation
enum CategoryResolutionResult {
    /// Category already exists, returns ID and name
    case existing(id: String, name: String)
    /// Category was created, returns new ID and name
    case created(id: String, name: String)
}

/// Result of subcategory resolution operation
enum SubcategoryResolutionResult {
    /// Subcategory already exists, returns ID
    case existing(id: String)
    /// Subcategory was created, returns new ID
    case created(id: String)
}
