//
//  BudgetSpendingCacheService.swift
//  AIFinanceManager
//
//  Phase 22: Persistent budget spending cache in CustomCategoryEntity.
//
//  PURPOSE:
//  Eliminates the O(N) scan in CategoryBudgetService.calculateSpent() by caching
//  the current-period spending total directly in CustomCategoryEntity.
//  The cache is invalidated (and the category's entry updated) whenever a transaction
//  belonging to that category is added, removed, or modified.
//
//  ARCHITECTURE:
//  - cachedSpentAmount: total expenses for this category in the current budget period
//  - cachedSpentUpdatedAt: when the cache was last valid
//  - cachedSpentCurrency: currency of the cached amount
//  - Cache is invalidated by transaction mutations via CategoryAggregateService
//  - Cache is rebuilt on: full import, currency change, budget period rollover
//
//  PERFORMANCE:
//  - Budget progress read: O(1) — read from CoreData entity field
//  - Cache update: O(1) per transaction (find entity by category name, increment amount)
//  - Cache rebuild: O(N × C) — only on import or currency change
//

import Foundation
import CoreData
import os

// MARK: - Service

/// Manages the `cachedSpentAmount` / `cachedSpentUpdatedAt` fields on `CustomCategoryEntity`.
/// All writes happen on background CoreData contexts; reads on viewContext.
final class BudgetSpendingCacheService: @unchecked Sendable {

    // MARK: - Dependencies

    private let stack: CoreDataStack
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "BudgetSpendingCacheService")

    // MARK: - Init

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - Public API

    /// Apply an added expense transaction: increment spending cache for its category.
    func applyAdded(_ transaction: Transaction, baseCurrency: String, budgetPeriodStart: Date?) {
        guard transaction.type == .expense, !transaction.category.isEmpty else { return }
        guard let periodStart = budgetPeriodStart else { return }
        guard isInCurrentPeriod(transaction.date, periodStart: periodStart) else { return }

        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount > 0 else { return }
        let category = transaction.category

        Task.detached(priority: .utility) { [weak self] in
            await self?.incrementSpent(
                categoryName: category,
                delta: amount,
                currency: baseCurrency
            )
        }
    }

    /// Apply a deleted expense transaction: decrement spending cache for its category.
    func applyDeleted(_ transaction: Transaction, baseCurrency: String, budgetPeriodStart: Date?) {
        guard transaction.type == .expense, !transaction.category.isEmpty else { return }
        guard let periodStart = budgetPeriodStart else { return }
        guard isInCurrentPeriod(transaction.date, periodStart: periodStart) else { return }

        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount > 0 else { return }
        let category = transaction.category

        Task.detached(priority: .utility) { [weak self] in
            await self?.incrementSpent(
                categoryName: category,
                delta: -amount,
                currency: baseCurrency
            )
        }
    }

    /// Apply an updated expense transaction: revert old amount, apply new.
    func applyUpdated(
        old: Transaction,
        new: Transaction,
        baseCurrency: String,
        budgetPeriodStart: (String) -> Date?
    ) {
        applyDeleted(old, baseCurrency: baseCurrency, budgetPeriodStart: budgetPeriodStart(old.category))
        applyAdded(new, baseCurrency: baseCurrency, budgetPeriodStart: budgetPeriodStart(new.category))
    }

    /// Invalidate the spending cache for a specific category (sets cachedSpentUpdatedAt to nil).
    /// Forces recalculation on next read via CategoryBudgetService.
    func invalidate(categoryName: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let context = self.stack.newBackgroundContext()
            await context.perform {
                let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
                request.predicate = NSPredicate(format: "name == %@", categoryName)
                request.fetchLimit = 1
                guard let entity = try? context.fetch(request).first else { return }
                // Direct mutation — safe inside outer await context.perform { }
                entity.cachedSpentUpdatedAt = nil
                entity.cachedSpentAmount = 0
                do {
                    if context.hasChanges { try context.save() }
                } catch {
                    Self.logger.error("BudgetSpendingCacheService.invalidate save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Full rebuild: recalculate spending for all budget categories in the current period.
    func rebuild(
        from transactions: [Transaction],
        categories: [CustomCategory],
        baseCurrency: String,
        budgetService: CategoryBudgetService
    ) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.performRebuild(
                transactions: transactions,
                categories: categories,
                baseCurrency: baseCurrency,
                budgetService: budgetService
            )
        }
    }

    /// Read the cached spent amount for a category.
    /// Returns nil if cache is invalid (not yet computed, currency mismatch, or stale period).
    /// - Parameter budgetPeriodStart: Start of the current budget period. Cache is invalid if
    ///   the last update was before this date (period rollover bug fix — Phase 36).
    @MainActor func cachedSpent(for categoryName: String, currency: String, budgetPeriodStart: Date? = nil) -> Double? {
        let context = stack.viewContext
        let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
        request.predicate = NSPredicate(format: "name == %@", categoryName)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return nil }
        // Cache invalid if currency doesn't match or never set
        guard entity.cachedSpentCurrency == currency,
              let updatedAt = entity.cachedSpentUpdatedAt else { return nil }
        // Phase 36: Cache invalid if it was last updated before the current budget period
        // (e.g., last month's spending cached but period rolled over to this month)
        if let periodStart = budgetPeriodStart, updatedAt < periodStart {
            return nil
        }
        return max(0, entity.cachedSpentAmount)
    }

    // MARK: - Private: Incremental Update

    private func incrementSpent(
        categoryName: String,
        delta: Double,
        currency: String
    ) async {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        await context.perform {
            let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
            request.predicate = NSPredicate(format: "name == %@", categoryName)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return }

            // Direct mutations — safe inside outer await context.perform { }
            // Invalidate cache if currency changes
            if entity.cachedSpentCurrency != currency {
                entity.cachedSpentAmount = 0
            }
            entity.cachedSpentAmount = max(0, entity.cachedSpentAmount + delta)
            entity.cachedSpentCurrency = currency
            entity.cachedSpentUpdatedAt = Date()

            do {
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("❌ [BudgetCache] increment save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Private: Full Rebuild

    private func performRebuild(
        transactions: [Transaction],
        categories: [CustomCategory],
        baseCurrency: String,
        budgetService: CategoryBudgetService
    ) async {
        Self.logger.debug("🔄 [BudgetCache] Rebuild START — \(categories.count) budget categories")

        let budgetCategories = categories.filter { $0.budgetAmount != nil && $0.type == .expense }
        guard !budgetCategories.isEmpty else { return }

        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        await context.perform {
            for category in budgetCategories {
                // Calculate spent for this category using CategoryBudgetService
                let spent = budgetService.calculateSpent(for: category, transactions: transactions)

                let request = NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
                request.predicate = NSPredicate(format: "name == %@", category.name)
                request.fetchLimit = 1

                guard let entity = try? context.fetch(request).first else { continue }
                // Direct mutations — safe inside outer await context.perform { }
                entity.cachedSpentAmount = spent
                entity.cachedSpentCurrency = baseCurrency
                entity.cachedSpentUpdatedAt = Date()
            }

            do {
                if context.hasChanges { try context.save() }
                Self.logger.debug("✅ [BudgetCache] Rebuild DONE — \(budgetCategories.count) categories updated")
            } catch {
                Self.logger.error("❌ [BudgetCache] Rebuild save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private func isInCurrentPeriod(_ dateString: String, periodStart: Date) -> Bool {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else { return false }
        return date >= periodStart && date <= Date()
    }

    private func resolveAmount(_ tx: Transaction, baseCurrency: String) -> Double {
        if tx.currency == baseCurrency { return tx.amount }
        if let c = tx.convertedAmount, c > 0 { return c }
        return CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) ?? tx.amount
    }
}
