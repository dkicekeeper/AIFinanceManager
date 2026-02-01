//
//  CategoryStyleCache.swift
//  AIFinanceManager
//
//  Global singleton cache for CategoryStyleHelper to avoid recreating on every render
//  OPTIMIZATION: Reduces object creation from 60fps × N categories to O(1) lookups
//

import SwiftUI

/// Pre-computed category style data
struct CategoryStyleData: Equatable {
    let coinColor: Color
    let coinBorderColor: Color
    let iconColor: Color
    let primaryColor: Color
    let lightBackgroundColor: Color
    let iconName: String
}

/// Singleton cache for category styles
@MainActor
final class CategoryStyleCache {

    // MARK: - Singleton

    static let shared = CategoryStyleCache()

    private init() {}

    // MARK: - Cache

    /// Cache key: "categoryName_transactionType"
    private var cache: [String: CategoryStyleData] = [:]

    /// Categories snapshot for invalidation detection
    private var cachedCategoriesHash: Int = 0

    // MARK: - Public Methods

    /// Get or compute style data for a category
    /// - Parameters:
    ///   - category: Category name
    ///   - type: Transaction type
    ///   - customCategories: All custom categories
    /// - Returns: Pre-computed style data
    func getStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        // Check if categories changed (invalidate cache)
        let categoriesHash = customCategories.map { $0.id }.hashValue
        if categoriesHash != cachedCategoriesHash {
            #if DEBUG
            print("🔄 [CategoryStyleCache] Categories changed - invalidating cache")
            #endif
            cache.removeAll()
            cachedCategoriesHash = categoriesHash
        }

        // Generate cache key
        let key = "\(category)_\(type.rawValue)"

        // Return from cache if exists
        if let cached = cache[key] {
            return cached
        }

        // Compute style data
        let styleData = computeStyleData(
            category: category,
            type: type,
            customCategories: customCategories
        )

        // Cache it
        cache[key] = styleData

        #if DEBUG
        print("💾 [CategoryStyleCache] Cached style for '\(category)' (\(type.rawValue))")
        #endif

        return styleData
    }

    /// Invalidate entire cache (call when categories change)
    func invalidateCache() {
        let count = cache.count
        cache.removeAll()
        cachedCategoriesHash = 0

        #if DEBUG
        print("🧹 [CategoryStyleCache] Cache invalidated - removed \(count) entries")
        #endif
    }

    /// Invalidate specific category
    /// - Parameters:
    ///   - category: Category name
    ///   - type: Transaction type
    func invalidateCategory(_ category: String, type: TransactionType) {
        let key = "\(category)_\(type.rawValue)"
        cache.removeValue(forKey: key)

        #if DEBUG
        print("🗑️ [CategoryStyleCache] Invalidated '\(category)' (\(type.rawValue))")
        #endif
    }

    // MARK: - Private Helpers

    /// Compute style data from scratch
    private func computeStyleData(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        // Special case: income
        if type == .income {
            return CategoryStyleData(
                coinColor: Color.green.opacity(0.3),
                coinBorderColor: Color.green.opacity(0.6),
                iconColor: Color.green,
                primaryColor: Color.green,
                lightBackgroundColor: Color.green.opacity(0.15),
                iconName: CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
            )
        }

        // Regular category
        let baseColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)

        return CategoryStyleData(
            coinColor: CategoryColors.hexColor(for: category, opacity: 0.3, customCategories: customCategories),
            coinBorderColor: CategoryColors.hexColor(for: category, opacity: 0.6, customCategories: customCategories),
            iconColor: baseColor,
            primaryColor: baseColor,
            lightBackgroundColor: CategoryColors.hexColor(for: category, opacity: 0.15, customCategories: customCategories),
            iconName: CategoryIcon.iconName(for: category, type: type, customCategories: customCategories)
        )
    }
}

// MARK: - CategoryStyleHelper Extension

extension CategoryStyleHelper {
    /// Create helper with cached style data
    /// OPTIMIZATION: Use this instead of direct init for repeated renders
    static func cached(
        category: String,
        type: TransactionType,
        customCategories: [CustomCategory]
    ) -> CategoryStyleData {
        CategoryStyleCache.shared.getStyleData(
            category: category,
            type: type,
            customCategories: customCategories
        )
    }
}
