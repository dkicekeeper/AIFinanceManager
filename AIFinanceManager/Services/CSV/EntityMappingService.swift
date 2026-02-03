//
//  EntityMappingService.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 2
//

import Foundation
import SwiftUI

/// Service for mapping and resolving entities (accounts, categories, subcategories)
/// Centralizes all lookup logic with LRU cache integration
/// Eliminates duplication of account/category resolution code (was 3 copies)
@MainActor
class EntityMappingService: EntityMappingServiceProtocol {

    // MARK: - Properties

    private let cache: ImportCacheManager

    // MARK: - Initialization

    init(cache: ImportCacheManager) {
        self.cache = cache
    }

    // MARK: - Account Resolution

    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping,
        accountsViewModel: AccountsViewModel?
    ) async -> AccountResolutionResult {

        // Reserved names (never create accounts with these names)
        let reservedNames = [
            String(localized: "category.other").lowercased(),
            "other",
            "другое"
        ]

        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()

        guard !normalizedName.isEmpty,
              !reservedNames.contains(normalizedName) else {
            return .skipped
        }

        // Check mapping first
        if let mappedId = mapping.accountMappings[name] {
            cache.cacheAccount(name: name, id: mappedId)
            return .existing(id: mappedId)
        }

        // Check cache
        if let cachedId = cache.getAccount(name: name) {
            return .existing(id: cachedId)
        }

        // Check AccountsViewModel
        if let accountsVM = accountsViewModel {
            if let account = accountsVM.accounts.first(where: {
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName
            }) {
                cache.cacheAccount(name: name, id: account.id)
                return .existing(id: account.id)
            }

            // Create new account with shouldCalculateFromTransactions=true for CSV imports
            await accountsVM.addAccount(
                name: name,
                initialBalance: 0.0,
                currency: currency,
                bankLogo: .none,
                shouldCalculateFromTransactions: true
            )

            // Get newly created account ID
            if let newAccount = accountsVM.accounts.first(where: {
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName
            }) {
                cache.cacheAccount(name: name, id: newAccount.id)
                return .created(id: newAccount.id)
            }
        }

        return .skipped
    }

    // MARK: - Category Resolution

    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult {

        // Check mapping first
        if let mappedName = mapping.categoryMappings[name] {
            return await resolveCategoryByName(
                mappedName,
                type: type,
                categoriesViewModel: categoriesViewModel
            )
        }

        // Resolve by actual name
        return await resolveCategoryByName(
            name,
            type: type,
            categoriesViewModel: categoriesViewModel
        )
    }

    private func resolveCategoryByName(
        _ name: String,
        type: TransactionType,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult {

        // Check cache
        if let cachedId = cache.getCategory(name: name, type: type) {
            return .existing(id: cachedId, name: name)
        }

        // Check existing categories
        if let existing = categoriesViewModel.customCategories.first(where: {
            $0.name == name && $0.type == type
        }) {
            cache.cacheCategory(name: name, type: type, id: existing.id)
            return .existing(id: existing.id, name: name)
        }

        // Create new category
        let iconName = CategoryIcon.iconName(
            for: name,
            type: type,
            customCategories: categoriesViewModel.customCategories
        )
        let colorHex = CategoryColors.hexColor(
            for: name,
            customCategories: categoriesViewModel.customCategories
        )
        let hexString = colorToHex(colorHex)

        let newCategory = CustomCategory(
            name: name,
            iconName: iconName,
            colorHex: hexString,
            type: type
        )

        var newCategories = categoriesViewModel.customCategories
        newCategories.append(newCategory)
        categoriesViewModel.updateCategories(newCategories)

        cache.cacheCategory(name: name, type: type, id: newCategory.id)
        return .created(id: newCategory.id, name: name)
    }

    // MARK: - Subcategory Resolution

    func resolveSubcategories(
        names: [String],
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> [SubcategoryResolutionResult] {

        var results: [SubcategoryResolutionResult] = []
        results.reserveCapacity(names.count)

        for name in names {
            let result = await resolveSubcategory(
                name: name,
                categoryId: categoryId,
                categoriesViewModel: categoriesViewModel
            )
            results.append(result)
        }

        return results
    }

    private func resolveSubcategory(
        name: String,
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> SubcategoryResolutionResult {

        // Check cache
        if let cachedId = cache.getSubcategory(name: name) {
            // Ensure link exists
            categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
                subcategoryId: cachedId,
                categoryId: categoryId
            )
            return .existing(id: cachedId)
        }

        // Check existing subcategories
        if let existing = categoriesViewModel.subcategories.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            cache.cacheSubcategory(name: name, id: existing.id)
            categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
                subcategoryId: existing.id,
                categoryId: categoryId
            )
            return .existing(id: existing.id)
        }

        // Create new subcategory
        let newSubcategory = categoriesViewModel.addSubcategory(name: name)
        cache.cacheSubcategory(name: name, id: newSubcategory.id)
        categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
            subcategoryId: newSubcategory.id,
            categoryId: categoryId
        )
        return .created(id: newSubcategory.id)
    }

    // MARK: - Helper

    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
