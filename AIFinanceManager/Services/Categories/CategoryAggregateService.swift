//
//  CategoryAggregateService.swift
//  AIFinanceManager
//
//  Phase 22: Activate CategoryAggregateEntity for persistent category spending totals.
//
//  PURPOSE:
//  Replaces the runtime O(N) calculation of category spending totals with pre-computed
//  CoreData aggregates that are maintained incrementally on each transaction change.
//
//  ARCHITECTURE:
//  - Maintains CategoryAggregateEntity records per (category, year, month) granularity
//  - On add: increments affected aggregates by transaction amount
//  - On delete: decrements affected aggregates
//  - On update: reverts old, applies new
//  - On bulkAdd / currency change: full rebuild from TransactionStore
//
//  PERFORMANCE:
//  - Per-transaction mutation: O(1) aggregate update (vs O(N) full scan)
//  - Category spending lookup: O(1) CoreData fetch by index
//  - Full rebuild: O(N) — only on import or currency change
//

import Foundation
import CoreData
import os

// MARK: - Domain Model

/// Monthly spending total for a single (category, year, month) combination.
/// Used by InsightsService to avoid O(N) transaction scans.
struct CategoryMonthlyAggregate: Equatable {
    let categoryName: String
    let year: Int
    let month: Int        // 1-12, 0 = all-time total
    let totalExpenses: Double
    let transactionCount: Int
    let currency: String
    let lastUpdated: Date
}

// MARK: - Service

/// Manages persistent CategoryAggregateEntity records in CoreData.
/// Thread-safe: all mutations happen on a background CoreData context,
/// reads happen on the viewContext (main thread) via @MainActor callers.
final class CategoryAggregateService: @unchecked Sendable {

    // MARK: - Dependencies

    private let stack: CoreDataStack
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CategoryAggregateService")

    // MARK: - Init

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - Public API

    /// Increment aggregate for an added expense transaction.
    /// No-op for non-expense transactions.
    func applyAdded(_ transaction: Transaction, baseCurrency: String) {
        guard transaction.type == .expense, !transaction.category.isEmpty else { return }
        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount != 0 else { return }
        let date = parseDate(transaction.date)
        Task.detached(priority: .utility) { [weak self, date] in
            await self?.increment(
                category: transaction.category,
                date: date,
                delta: amount,
                currency: baseCurrency
            )
        }
    }

    /// Decrement aggregate for a deleted expense transaction.
    func applyDeleted(_ transaction: Transaction, baseCurrency: String) {
        guard transaction.type == .expense, !transaction.category.isEmpty else { return }
        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount != 0 else { return }
        let date = parseDate(transaction.date)
        Task.detached(priority: .utility) { [weak self, date] in
            await self?.increment(
                category: transaction.category,
                date: date,
                delta: -amount,
                currency: baseCurrency
            )
        }
    }

    /// Revert old transaction's contribution and apply new transaction's contribution.
    func applyUpdated(old: Transaction, new: Transaction, baseCurrency: String) {
        applyDeleted(old, baseCurrency: baseCurrency)
        applyAdded(new, baseCurrency: baseCurrency)
    }

    /// Full rebuild from all transactions. Called after CSV import or base currency change.
    /// Runs on background context to avoid blocking the main thread.
    func rebuild(from transactions: [Transaction], baseCurrency: String) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.performRebuild(transactions: transactions, baseCurrency: baseCurrency)
        }
    }

    /// Fetch monthly spending totals for a specific (year, month) pair.
    /// Returns sorted by totalExpenses descending.
    /// Runs on viewContext (main thread safe for @MainActor callers).
    func fetchMonthly(year: Int, month: Int, currency: String) -> [CategoryMonthlyAggregate] {
        let context = stack.viewContext
        let request = CategoryAggregateEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "year == %d AND month == %d AND currency == %@",
            Int16(year), Int16(month), currency
        )
        request.sortDescriptors = [NSSortDescriptor(key: "totalAmount", ascending: false)]
        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                CategoryMonthlyAggregate(
                    categoryName: entity.categoryName ?? "",
                    year: Int(entity.year),
                    month: Int(entity.month),
                    totalExpenses: entity.totalAmount,
                    transactionCount: Int(entity.transactionCount),
                    currency: entity.currency ?? currency,
                    lastUpdated: entity.lastUpdated ?? Date()
                )
            }
        } catch {
            Self.logger.error("❌ [CategoryAgg] fetchMonthly failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetch all-time totals per category (year=0, month=0).
    func fetchAllTime(currency: String) -> [CategoryMonthlyAggregate] {
        let context = stack.viewContext
        let request = CategoryAggregateEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "year == 0 AND month == 0 AND currency == %@",
            currency
        )
        request.sortDescriptors = [NSSortDescriptor(key: "totalAmount", ascending: false)]
        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                CategoryMonthlyAggregate(
                    categoryName: entity.categoryName ?? "",
                    year: 0,
                    month: 0,
                    totalExpenses: entity.totalAmount,
                    transactionCount: Int(entity.transactionCount),
                    currency: entity.currency ?? currency,
                    lastUpdated: entity.lastUpdated ?? Date()
                )
            }
        } catch {
            Self.logger.error("❌ [CategoryAgg] fetchAllTime failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetch spending totals for a date range. Groups by category, returns sorted desc.
    /// Used by InsightsService instead of O(N) transaction filtering.
    func fetchRange(
        from startDate: Date,
        to endDate: Date,
        currency: String
    ) -> [CategoryMonthlyAggregate] {
        let calendar = Calendar.current
        var months: [(year: Int, month: Int)] = []

        // Enumerate months in range
        var current = startDate
        while current <= endDate {
            let comps = calendar.dateComponents([.year, .month], from: current)
            if let y = comps.year, let m = comps.month {
                months.append((y, m))
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        guard !months.isEmpty else { return [] }

        // Batch fetch all needed months
        let yearMonthPairs = months.map { "(\($0.year), \($0.month))" }.joined(separator: ", ")
        _ = yearMonthPairs  // used below in predicate building

        let context = stack.viewContext
        let request = CategoryAggregateEntity.fetchRequest()

        // Build OR predicate for each (year, month) pair
        let subPredicates: [NSPredicate] = months.map { ym in
            NSPredicate(
                format: "year == %d AND month == %d AND currency == %@",
                Int16(ym.year), Int16(ym.month), currency
            )
        }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subPredicates)
        request.sortDescriptors = [NSSortDescriptor(key: "categoryName", ascending: true)]

        do {
            let entities = try context.fetch(request)

            // Aggregate by category (sum across multiple months)
            var byCategory: [String: (total: Double, count: Int)] = [:]
            for entity in entities {
                let name = entity.categoryName ?? ""
                let existing = byCategory[name] ?? (0, 0)
                byCategory[name] = (
                    existing.total + entity.totalAmount,
                    existing.count + Int(entity.transactionCount)
                )
            }

            return byCategory
                .map { name, value in
                    CategoryMonthlyAggregate(
                        categoryName: name,
                        year: 0,
                        month: 0,
                        totalExpenses: value.total,
                        transactionCount: value.count,
                        currency: currency,
                        lastUpdated: Date()
                    )
                }
                .sorted { $0.totalExpenses > $1.totalExpenses }
        } catch {
            Self.logger.error("❌ [CategoryAgg] fetchRange failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Private: Incremental Update

    /// Increment (or decrement) the aggregate for the given category + date.
    /// Maintains 3 granularity levels: monthly, yearly, all-time.
    private func increment(
        category: String,
        date: Date?,
        delta: Double,
        currency: String
    ) async {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        await context.perform {
            let calendar = Calendar.current
            let comps: DateComponents?
            if let date = date {
                comps = calendar.dateComponents([.year, .month], from: date)
            } else {
                comps = nil
            }

            let year = Int16(comps?.year ?? 0)
            let month = Int16(comps?.month ?? 0)

            // 1. Monthly aggregate (e.g., year=2026, month=2)
            if year > 0 && month > 0 {
                self.upsertAggregate(
                    category: category,
                    year: year,
                    month: month,
                    delta: delta,
                    currency: currency,
                    context: context
                )
            }

            // 2. Yearly aggregate (year=2026, month=0)
            if year > 0 {
                self.upsertAggregate(
                    category: category,
                    year: year,
                    month: 0,
                    delta: delta,
                    currency: currency,
                    context: context
                )
            }

            // 3. All-time aggregate (year=0, month=0)
            self.upsertAggregate(
                category: category,
                year: 0,
                month: 0,
                delta: delta,
                currency: currency,
                context: context
            )

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Self.logger.error("❌ [CategoryAgg] increment save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Upsert a single CategoryAggregateEntity: find existing or create, add delta.
    private func upsertAggregate(
        category: String,
        year: Int16,
        month: Int16,
        delta: Double,
        currency: String,
        context: NSManagedObjectContext
    ) {
        let aggregateId = "\(category)__\(year)_\(month)_0"

        let request = CategoryAggregateEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND currency == %@",
            aggregateId, currency
        )
        request.fetchLimit = 1

        do {
            let existing = try context.fetch(request).first
            let entity = existing ?? {
                let e = CategoryAggregateEntity(context: context)
                e.id = aggregateId
                e.categoryName = category
                e.year = year
                e.month = month
                e.day = 0
                e.currency = currency
                e.totalAmount = 0
                e.transactionCount = 0
                return e
            }()

            entity.totalAmount += delta
            entity.transactionCount += (delta >= 0 ? 1 : -1)
            // Clamp to avoid negative counts from timing issues
            if entity.transactionCount < 0 { entity.transactionCount = 0 }
            entity.lastUpdated = Date()
        } catch {
            Self.logger.error("❌ [CategoryAgg] upsert failed id=\(aggregateId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private: Full Rebuild

    /// Delete all CategoryAggregateEntity records and recompute from scratch.
    private func performRebuild(transactions: [Transaction], baseCurrency: String) async {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let calendar = Calendar.current

        Self.logger.debug("🔄 [CategoryAgg] Rebuild START — \(transactions.count) transactions, currency=\(baseCurrency, privacy: .public)")

        await context.perform {
            // 1. Delete all existing aggregates
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "CategoryAggregateEntity")
            )
            deleteRequest.resultType = .resultTypeCount
            do {
                _ = try context.execute(deleteRequest)
                context.reset()
            } catch {
                Self.logger.error("❌ [CategoryAgg] batch delete failed: \(error.localizedDescription, privacy: .public)")
            }

            // 2. Compute new aggregates from scratch
            // Keyed by: "category__year_month_0" or "category__year_0_0" or "category__0_0_0"
            typealias AggKey = String
            struct AggValue {
                var total: Double = 0
                var count: Int32 = 0
            }
            var monthly: [AggKey: AggValue] = [:]
            var yearly: [AggKey: AggValue] = [:]
            var allTime: [AggKey: AggValue] = [:]

            let dateFormatter = DateFormatters.dateFormatter

            for tx in transactions {
                guard tx.type == .expense, !tx.category.isEmpty else { continue }

                let amount: Double
                if tx.currency == baseCurrency {
                    amount = tx.amount
                } else if let converted = tx.convertedAmount, converted > 0 {
                    amount = converted
                } else {
                    amount = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) ?? tx.amount
                }

                let cat = tx.category
                let comps: DateComponents?
                if let date = dateFormatter.date(from: tx.date) {
                    comps = calendar.dateComponents([.year, .month], from: date)
                } else {
                    comps = nil
                }

                let year = Int16(comps?.year ?? 0)
                let month = Int16(comps?.month ?? 0)

                // Monthly
                if year > 0 && month > 0 {
                    let key = "\(cat)__\(year)_\(month)_0"
                    monthly[key, default: AggValue()].total += amount
                    monthly[key, default: AggValue()].count += 1
                }

                // Yearly
                if year > 0 {
                    let key = "\(cat)__\(year)_0_0"
                    yearly[key, default: AggValue()].total += amount
                    yearly[key, default: AggValue()].count += 1
                }

                // All-time
                let key = "\(cat)__0_0_0"
                allTime[key, default: AggValue()].total += amount
                allTime[key, default: AggValue()].count += 1
            }

            // 3. Persist aggregates
            let now = Date()

            func persist(_ dict: [AggKey: AggValue], year: Int16? = nil, month: Int16? = nil) {
                for (key, value) in dict {
                    guard value.total > 0 else { continue }
                    // Parse category from key: "cat__year_month_0"
                    let parts = key.components(separatedBy: "__")
                    guard parts.count >= 2 else { continue }
                    let cat = parts[0]
                    let timeParts = parts[1].components(separatedBy: "_")
                    guard timeParts.count == 3,
                          let yr = Int16(timeParts[0]),
                          let mo = Int16(timeParts[1]) else { continue }

                    let entity = CategoryAggregateEntity(context: context)
                    entity.id = "\(cat)__\(yr)_\(mo)_0"
                    entity.categoryName = cat
                    entity.subcategoryName = nil
                    entity.year = yr
                    entity.month = mo
                    entity.day = 0
                    entity.totalAmount = value.total
                    entity.transactionCount = value.count
                    entity.currency = baseCurrency
                    entity.lastUpdated = now
                }
            }

            persist(monthly)
            persist(yearly)
            persist(allTime)

            do {
                if context.hasChanges {
                    try context.save()
                }
                Self.logger.debug("✅ [CategoryAgg] Rebuild DONE — monthly=\(monthly.count), yearly=\(yearly.count), allTime=\(allTime.count)")
            } catch {
                Self.logger.error("❌ [CategoryAgg] Rebuild save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private func resolveAmount(_ tx: Transaction, baseCurrency: String) -> Double {
        if tx.currency == baseCurrency { return tx.amount }
        if let c = tx.convertedAmount, c > 0 { return c }
        return CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) ?? tx.amount
    }

    private func parseDate(_ dateString: String) -> Date? {
        return DateFormatters.dateFormatter.date(from: dateString)
    }
}
