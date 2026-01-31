//
//  TransactionStorageCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation
import Combine

/// Service responsible for coordinating storage operations (save/load)
/// Extracted from TransactionsViewModel to follow Single Responsibility Principle
@MainActor
class TransactionStorageCoordinator: TransactionStorageCoordinatorProtocol {

    // MARK: - Dependencies

    private weak var delegate: TransactionStorageDelegate?

    // MARK: - Save Debouncing

    private var saveDebouncer: AnyCancellable?
    private var saveCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(delegate: TransactionStorageDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Public API

    func loadFromStorage() async {
        guard let delegate = delegate else { return }

        // OPTIMIZATION: Load recent transactions first for fast UI display
        let now = Date()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .month, value: -delegate.displayMonthsRange, to: now) else {
            // Fallback to loading all transactions
            await MainActor.run {
                delegate.allTransactions = delegate.repository.loadTransactions(dateRange: nil)
                delegate.displayTransactions = delegate.allTransactions
                delegate.hasOlderTransactions = false
            }
            loadOtherData()
            return
        }

        let recentDateRange = DateInterval(start: startDate, end: now)

        // Load recent transactions for UI (fast)
        await MainActor.run {
            delegate.displayTransactions = delegate.repository.loadTransactions(dateRange: recentDateRange)
        }

        // Load ALL transactions synchronously in background to ensure data is ready before migration
        // CRITICAL FIX: Use .value to wait for completion so allTransactions is populated
        // before initializeCategoryAggregates() runs
        await Task.detached(priority: .utility) { [weak self] in
            guard let self = self, let delegate = self.delegate else { return }

            let allTxns = delegate.repository.loadTransactions(dateRange: nil)

            await MainActor.run {
                delegate.allTransactions = allTxns
                delegate.hasOlderTransactions = allTxns.count > delegate.displayTransactions.count

                if delegate.hasOlderTransactions {
                }

                // Recalculate caches with full data
                delegate.invalidateCaches()
                delegate.rebuildIndexes()
            }
        }.value

        loadOtherData()
    }

    func loadOlderTransactions() {
        guard let delegate = delegate else { return }
        guard delegate.hasOlderTransactions else {
            return
        }

        // displayTransactions should now include all transactions
        delegate.displayTransactions = delegate.allTransactions
        delegate.hasOlderTransactions = false
    }

    func saveToStorage() {
        guard let delegate = delegate else { return }

        Task.detached(priority: .utility) {
            PerformanceProfiler.start("saveToStorage")

            let transactions = await MainActor.run { delegate.allTransactions }
            let rules = await MainActor.run { delegate.categoryRules }
            let accs = await MainActor.run { delegate.accounts }
            let categories = await MainActor.run { delegate.customCategories }
            let series = await MainActor.run { delegate.recurringSeries }
            let occurrences = await MainActor.run { delegate.recurringOccurrences }

            // НЕ сохраняем подкатегории и связи здесь - они управляются CategoriesViewModel
            // let subcats = await MainActor.run { delegate.subcategories }
            // let catLinks = await MainActor.run { delegate.categorySubcategoryLinks }
            // let txLinks = await MainActor.run { delegate.transactionSubcategoryLinks }

            await MainActor.run {
                delegate.repository.saveTransactions(transactions)
                delegate.repository.saveCategoryRules(rules)
                delegate.repository.saveAccounts(accs)
                delegate.repository.saveCategories(categories)
                delegate.repository.saveRecurringSeries(series)
                delegate.repository.saveRecurringOccurrences(occurrences)
                // Подкатегории и связи сохраняются через CategoriesViewModel
                // delegate.repository.saveSubcategories(subcats)
                // delegate.repository.saveCategorySubcategoryLinks(catLinks)
                // delegate.repository.saveTransactionSubcategoryLinks(txLinks)
            }

            PerformanceProfiler.end("saveToStorage")
        }
    }

    func saveToStorageDebounced() {
        saveDebouncer?.cancel()
        saveDebouncer = Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveToStorage()
            }
    }

    func saveToStorageSync() {
        guard let delegate = delegate else { return }

        PerformanceProfiler.start("saveToStorageSync")

        // Синхронно сохраняем все данные
        saveTransactionsSync(delegate.allTransactions)
        saveCategoryRulesSync(delegate.categoryRules)
        saveAccountsSync(delegate.accounts)
        saveCategoriesSync(delegate.customCategories)
        saveRecurringSeriesSync(delegate.recurringSeries)
        saveRecurringOccurrencesSync(delegate.recurringOccurrences)
        // Подкатегории и связи сохраняются через CategoriesViewModel

        PerformanceProfiler.end("saveToStorageSync")
    }

    // MARK: - Private Helper Methods

    private func loadOtherData() {
        guard let delegate = delegate else { return }

        delegate.categoryRules = delegate.repository.loadCategoryRules()

        // Load accounts from AccountBalanceService (single source of truth)
        delegate.accounts = delegate.accountBalanceService.accounts

        // Note: Initial balances will be calculated after ALL transactions are loaded
        // This happens asynchronously in the background task above

        delegate.customCategories = delegate.repository.loadCategories()
        delegate.recurringSeries = delegate.repository.loadRecurringSeries()
        delegate.recurringOccurrences = delegate.repository.loadRecurringOccurrences()
        delegate.subcategories = delegate.repository.loadSubcategories()
        delegate.categorySubcategoryLinks = delegate.repository.loadCategorySubcategoryLinks()
        delegate.transactionSubcategoryLinks = delegate.repository.loadTransactionSubcategoryLinks()

        // Calculate initial balances with displayTransactions for now
        // Will be recalculated when all transactions load in background
        for account in delegate.accounts {
            if delegate.initialAccountBalances[account.id] == nil {
                // Calculate the sum of display transactions for this account (temporary)
                let transactionsSum = delegate.displayTransactions
                    .filter { $0.accountId == account.id || $0.targetAccountId == account.id }
                    .reduce(0.0) { sum, tx in
                        if tx.accountId == account.id {
                            return sum + (tx.type == .income ? tx.amount : -tx.amount)
                        } else if tx.targetAccountId == account.id {
                            return sum + tx.amount // Transfer in
                        }
                        return sum
                    }
                let initialBalance = account.balance - transactionsSum
                delegate.initialAccountBalances[account.id] = initialBalance
            }
        }

        // NOTE: Do NOT call recalculateAccountBalances() here!
        // Balances are already calculated and saved in Core Data.
        // They will be recalculated when all transactions finish loading in background

        // PERFORMANCE: Do NOT call rebuildIndexes() here!
        // At this point allTransactions is still empty (loading in background task).
        // Indexes will be built when background task completes (see loadFromStorage Task).

        // Precompute currency conversions in background for better UI performance
        delegate.precomputeCurrencyConversions()
    }

    private func saveTransactionsSync(_ transactions: [Transaction]) {
        guard let delegate = delegate else { return }

        if let coreDataRepo = delegate.repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveTransactionsSync(transactions)
            } catch {
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            delegate.repository.saveTransactions(transactions)
        }
    }

    private func saveCategoryRulesSync(_ rules: [CategoryRule]) {
        guard let delegate = delegate else { return }
        delegate.repository.saveCategoryRules(rules)
    }

    private func saveAccountsSync(_ accounts: [Account]) {
        guard let delegate = delegate else { return }

        if let coreDataRepo = delegate.repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveAccountsSync(accounts)
            } catch {
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            delegate.repository.saveAccounts(accounts)
        }
    }

    private func saveCategoriesSync(_ categories: [CustomCategory]) {
        guard let delegate = delegate else { return }

        if let coreDataRepo = delegate.repository as? CoreDataRepository {
            do {
                try coreDataRepo.saveCategoriesSync(categories)
            } catch {
                // Critical error - log but don't fallback to UserDefaults
                // This ensures data consistency with the primary storage
            }
        } else {
            // For non-CoreData repositories (e.g., UserDefaultsRepository in tests)
            // use the standard async save method
            delegate.repository.saveCategories(categories)
        }
    }

    private func saveRecurringSeriesSync(_ series: [RecurringSeries]) {
        guard let delegate = delegate else { return }
        delegate.repository.saveRecurringSeries(series)
    }

    private func saveRecurringOccurrencesSync(_ occurrences: [RecurringOccurrence]) {
        guard let delegate = delegate else { return }
        delegate.repository.saveRecurringOccurrences(occurrences)
    }
}
