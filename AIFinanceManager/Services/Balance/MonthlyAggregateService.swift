//
//  MonthlyAggregateService.swift
//  AIFinanceManager
//
//  Phase 22: Persistent monthly income/expense aggregates for InsightsService.
//
//  PURPOSE:
//  Eliminates the O(N × M) computation in InsightsService.computeMonthlyDataPoints().
//  Stores pre-computed (year, month) → (totalIncome, totalExpenses) tuples in CoreData.
//  InsightsService reads these O(M) records instead of re-scanning all N transactions.
//
//  ARCHITECTURE:
//  - Uses MonthlyAggregateEntity (new CoreData entity added in Phase 22)
//  - Incremental updates: on add/delete/update only touch 1 month record
//  - Full rebuild: on CSV import or base currency change (O(N) single pass)
//  - Fetch API: read aggregates for a date range (O(M) where M = number of months)
//
//  PERFORMANCE IMPACT:
//  - InsightsService "Last Year" chart: O(12k × 12 months) → O(12 months)
//  - Per-transaction mutation: O(1) aggregate update
//

import Foundation
import CoreData
import os

// MARK: - Domain Model

/// Monthly income+expense totals for InsightsService chart data.
struct MonthlyFinancialAggregate: Equatable, Identifiable {
    var id: String { "\(year)-\(String(format: "%02d", month))-\(currency)" }
    let year: Int
    let month: Int          // 1-12
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let transactionCount: Int
    let currency: String
    let lastUpdated: Date

    // Phase 36: Cached DateFormatters — avoid allocation per computed property access
    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        f.locale = .current
        return f
    }()
    private static let shortLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = .current
        return f
    }()

    /// Label for chart display: "Jan 2026"
    var label: String {
        guard let date = Calendar.current.date(
            from: DateComponents(year: year, month: month, day: 1)
        ) else { return "\(month)/\(year)" }
        return Self.labelFormatter.string(from: date)
    }

    /// Short label for chart axis: "Jan"
    var shortLabel: String {
        guard let date = Calendar.current.date(
            from: DateComponents(year: year, month: month, day: 1)
        ) else { return "\(month)" }
        return Self.shortLabelFormatter.string(from: date)
    }
}

// MARK: - Service

/// Manages persistent MonthlyAggregateEntity records in CoreData.
/// All writes happen on background contexts; reads on viewContext.
final class MonthlyAggregateService: @unchecked Sendable {

    // MARK: - Dependencies

    private let stack: CoreDataStack
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "MonthlyAggregateService")

    // MARK: - Init

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - Public API: Mutations

    /// Apply an added transaction: increment the (year, month) aggregate.
    func applyAdded(_ transaction: Transaction, baseCurrency: String) {
        guard isFinancialTransaction(transaction) else { return }
        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount != 0 else { return }
        let date = parseDate(transaction.date)
        let txType = transaction.type
        Task.detached(priority: .utility) { [weak self, date] in
            await self?.increment(
                date: date,
                income: txType == .income ? amount : 0,
                expenses: txType == .expense ? amount : 0,
                currency: baseCurrency
            )
        }
    }

    /// Apply a deleted transaction: decrement the (year, month) aggregate.
    func applyDeleted(_ transaction: Transaction, baseCurrency: String) {
        guard isFinancialTransaction(transaction) else { return }
        let amount = resolveAmount(transaction, baseCurrency: baseCurrency)
        guard amount != 0 else { return }
        let date = parseDate(transaction.date)
        let txType = transaction.type
        Task.detached(priority: .utility) { [weak self, date] in
            await self?.increment(
                date: date,
                income: txType == .income ? -amount : 0,
                expenses: txType == .expense ? -amount : 0,
                currency: baseCurrency
            )
        }
    }

    /// Apply an updated transaction: revert old, apply new.
    func applyUpdated(old: Transaction, new: Transaction, baseCurrency: String) {
        applyDeleted(old, baseCurrency: baseCurrency)
        applyAdded(new, baseCurrency: baseCurrency)
    }

    /// Full rebuild from all transactions. Called after CSV import or base currency change.
    func rebuild(from transactions: [Transaction], baseCurrency: String) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.performRebuild(transactions: transactions, baseCurrency: baseCurrency)
        }
    }

    // MARK: - Public API: Reads

    /// Fetch monthly aggregates for the last N months ending at `anchor` date.
    /// Returns results sorted chronologically. Missing months return zero-value entries.
    func fetchLast(
        _ months: Int,
        anchor: Date = Date(),
        currency: String
    ) -> [MonthlyFinancialAggregate] {
        let calendar = Calendar.current
        let anchorStart = startOfMonth(calendar, for: anchor)
        guard let startDate = calendar.date(byAdding: .month, value: -(months - 1), to: anchorStart) else { return [] }
        return fetchRange(from: startDate, to: anchor, currency: currency)
    }

    /// Fetch monthly aggregates between startDate and endDate (inclusive).
    /// Uses a single range predicate to avoid SQLite expression-tree limits on large windows.
    func fetchRange(
        from startDate: Date,
        to endDate: Date,
        currency: String
    ) -> [MonthlyFinancialAggregate] {
        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.year, .month], from: startDate)
        let endComps   = calendar.dateComponents([.year, .month], from: endDate)
        guard let startYear = startComps.year, let startMonth = startComps.month,
              let endYear   = endComps.year,   let endMonth   = endComps.month else { return [] }

        // Guard: empty range
        guard endYear * 100 + endMonth >= startYear * 100 + startMonth else { return [] }

        let context = stack.viewContext
        let request = MonthlyAggregateEntity.fetchRequest()

        // Single range predicate — no OR fan-out regardless of window size
        request.predicate = NSPredicate(
            format: """
                currency == %@ AND year > 0 AND month > 0
                AND (year > %d OR (year == %d AND month >= %d))
                AND (year < %d OR (year == %d AND month <= %d))
            """,
            currency,
            startYear, startYear, startMonth,
            endYear,   endYear,   endMonth
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "year",  ascending: true),
            NSSortDescriptor(key: "month", ascending: true)
        ]
        request.fetchBatchSize = 200

        do {
            let entities = try context.fetch(request)
            return entities.map { e in
                MonthlyFinancialAggregate(
                    year: Int(e.year),
                    month: Int(e.month),
                    totalIncome: e.totalIncome,
                    totalExpenses: e.totalExpenses,
                    netFlow: e.totalIncome - e.totalExpenses,
                    transactionCount: Int(e.transactionCount),
                    currency: e.currency ?? currency,
                    lastUpdated: e.lastUpdated ?? Date()
                )
            }
        } catch {
            Self.logger.error("❌ [MonthlyAgg] fetchRange failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Private: Incremental Update

    private func increment(
        date: Date?,
        income: Double,
        expenses: Double,
        currency: String
    ) async {
        guard let date = date else { return }
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return }

        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        await context.perform {
            self.upsertMonthly(
                year: Int16(year),
                month: Int16(month),
                incomeDelta: income,
                expensesDelta: expenses,
                currency: currency,
                context: context
            )
            do {
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("❌ [MonthlyAgg] increment save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func upsertMonthly(
        year: Int16,
        month: Int16,
        incomeDelta: Double,
        expensesDelta: Double,
        currency: String,
        context: NSManagedObjectContext
    ) {
        let entityId = "monthly_\(year)_\(month)_\(currency)"
        let request = MonthlyAggregateEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entityId)
        request.fetchLimit = 1

        do {
            let existing = try context.fetch(request).first
            let entity = existing ?? {
                let e = MonthlyAggregateEntity(context: context)
                e.id = entityId
                e.year = year
                e.month = month
                e.currency = currency
                e.totalIncome = 0
                e.totalExpenses = 0
                e.netFlow = 0
                e.transactionCount = 0
                return e
            }()

            entity.totalIncome = max(0, entity.totalIncome + incomeDelta)
            entity.totalExpenses = max(0, entity.totalExpenses + expensesDelta)
            entity.netFlow = entity.totalIncome - entity.totalExpenses
            entity.transactionCount += (incomeDelta != 0 || expensesDelta != 0) ? 1 : 0
            entity.lastUpdated = Date()
        } catch {
            Self.logger.error("❌ [MonthlyAgg] upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private: Full Rebuild

    private func performRebuild(transactions: [Transaction], baseCurrency: String) async {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let calendar = Calendar.current

        Self.logger.debug("🔄 [MonthlyAgg] Rebuild START — \(transactions.count) transactions")

        await context.perform {
            // 1. Delete all existing monthly aggregates
            // NOTE: Must use .resultTypeObjectIDs (not .resultTypeCount) and merge deleted IDs
            // into viewContext. Using NSBatchDeleteRequest without merging leaves stale faults
            // in viewContext. Calling context.reset() after NSBatchDeleteRequest on a fresh
            // background context interferes with the persistent store coordinator's SQLite
            // row cache while the FRC is concurrently firing faults — causing:
            // "Object TransactionEntity/pXXXX persistent store is not reachable" crash.
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: "MonthlyAggregateEntity")
            )
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let deleteResult = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let deletedIDs = deleteResult?.result as? [NSManagedObjectID] ?? []
                if !deletedIDs.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                        into: [self.stack.viewContext]
                    )
                }
            } catch {
                Self.logger.error("❌ [MonthlyAgg] batch delete failed: \(error.localizedDescription, privacy: .public)")
            }

            // 2. Single pass: group by (year, month)
            struct MonthAcc {
                var income: Double = 0
                var expenses: Double = 0
                var count: Int32 = 0
            }
            var acc: [String: MonthAcc] = [:]

            let dateFormatter = DateFormatters.dateFormatter

            for tx in transactions {
                guard self.isFinancialTransaction(tx) else { continue }
                let amount = self.resolveAmount(tx, baseCurrency: baseCurrency)
                guard amount > 0 else { continue }

                guard let date = dateFormatter.date(from: tx.date) else { continue }
                let comps = calendar.dateComponents([.year, .month], from: date)
                guard let year = comps.year, let month = comps.month else { continue }

                let key = "monthly_\(year)_\(month)_\(baseCurrency)"
                var entry = acc[key] ?? MonthAcc()
                switch tx.type {
                case .income:       entry.income += amount
                case .expense:      entry.expenses += amount
                default:            break
                }
                entry.count += 1
                acc[key] = entry
            }

            // 3. Persist
            let now = Date()
            for (key, value) in acc {
                // Parse year/month from key "monthly_2026_2_KZT"
                let parts = key.components(separatedBy: "_")
                guard parts.count >= 4,
                      let year = Int16(parts[1]),
                      let month = Int16(parts[2]) else { continue }

                let e = MonthlyAggregateEntity(context: context)
                e.id = key
                e.year = year
                e.month = month
                e.currency = baseCurrency
                e.totalIncome = value.income
                e.totalExpenses = value.expenses
                e.netFlow = value.income - value.expenses
                e.transactionCount = value.count
                e.lastUpdated = now
            }

            do {
                if context.hasChanges { try context.save() }
                Self.logger.debug("✅ [MonthlyAgg] Rebuild DONE — \(acc.count) month records")
            } catch {
                Self.logger.error("❌ [MonthlyAgg] Rebuild save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private func isFinancialTransaction(_ tx: Transaction) -> Bool {
        tx.type == .income || tx.type == .expense
    }

    private func resolveAmount(_ tx: Transaction, baseCurrency: String) -> Double {
        if tx.currency == baseCurrency { return tx.amount }
        if let c = tx.convertedAmount, c > 0 { return c }
        return CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) ?? tx.amount
    }

    private func parseDate(_ dateString: String) -> Date? {
        return DateFormatters.dateFormatter.date(from: dateString)
    }

    private func startOfMonth(_ calendar: Calendar, for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }
}
