//
//  BalanceCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 4
//
//  SINGLE ENTRY POINT for all balance operations
//  Coordinates between Store, Engine, Queue, and Cache
//  Provides unified API for balance management
//

import Foundation
import Combine

// MARK: - Balance Coordinator

/// Main coordinator for balance management
/// Facade pattern - hides complexity of balance calculation system
/// All balance operations should go through this coordinator
@MainActor
final class BalanceCoordinator: BalanceCoordinatorProtocol {

    // MARK: - Published State

    @Published private(set) var balances: [String: Double] = [:]

    // MARK: - Dependencies

    private let store: BalanceStore
    private let engine: BalanceCalculationEngine
    private let queue: BalanceUpdateQueue
    private let cache: BalanceCacheManager
    private let repository: DataRepositoryProtocol

    // MARK: - State

    private var optimisticUpdates: [UUID: OptimisticUpdate] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var lastUpdateTime: Date?

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol,
        cacheManager: TransactionCacheManager? = nil
    ) {
        self.repository = repository
        self.store = BalanceStore()
        self.engine = BalanceCalculationEngine(cacheManager: cacheManager)
        self.queue = BalanceUpdateQueue()
        self.cache = BalanceCacheManager()

        setupBindings()

        #if DEBUG
        print("✅ BalanceCoordinator initialized")
        #endif
    }

    // MARK: - Setup

    private func setupBindings() {
        // Subscribe to store updates and publish to our @Published property
        store.$balances
            .assign(to: \.balances, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Account Management

    func registerAccounts(_ accounts: [Account]) async {
        let accountBalances = accounts.map { AccountBalance.from($0) }
        store.registerAccounts(accountBalances)

        // Initialize cache
        let initialBalances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })
        cache.setBalances(initialBalances)

        #if DEBUG
        print("📝 Registered \(accounts.count) accounts")
        #endif
    }

    func removeAccount(_ accountId: String) async {
        store.removeAccount(accountId)
        cache.invalidate(accountId: accountId)

        #if DEBUG
        print("🗑️ Removed account: \(accountId)")
        #endif
    }

    // MARK: - Transaction Updates

    func updateForTransaction(
        _ transaction: Transaction,
        operation: TransactionUpdateOperation,
        priority: BalanceQueueRequest.Priority = .high
    ) async {
        // Determine affected accounts
        var affectedAccounts = Set<String>()

        switch transaction.type {
        case .income, .expense:
            if let accountId = transaction.accountId {
                affectedAccounts.insert(accountId)
            }

        case .internalTransfer:
            if let sourceId = transaction.accountId {
                affectedAccounts.insert(sourceId)
            }
            if let targetId = transaction.targetAccountId {
                affectedAccounts.insert(targetId)
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            if let accountId = transaction.accountId {
                affectedAccounts.insert(accountId)
            }
        }

        // Track affected accounts for smart invalidation
        cache.trackAffectedAccounts(for: transaction, affectedAccounts: affectedAccounts)

        // Create update request
        let request = BalanceQueueRequest(
            accountIds: affectedAccounts,
            operation: .transaction(operation),
            priority: priority
        )

        // Enqueue update
        await queue.enqueue(request)

        // For immediate priority, process synchronously
        if priority == .immediate {
            await processUpdateRequest(request)
        }

        #if DEBUG
        print("📨 Queued transaction update: \(transaction.id), affected accounts: \(affectedAccounts.count)")
        #endif
    }

    func updateForTransactions(
        _ transactions: [Transaction],
        operation: TransactionUpdateOperation,
        priority: BalanceQueueRequest.Priority = .normal
    ) async {
        guard !transactions.isEmpty else { return }

        // Collect all affected accounts
        var allAffectedAccounts = Set<String>()

        for transaction in transactions {
            switch transaction.type {
            case .income, .expense:
                if let accountId = transaction.accountId {
                    allAffectedAccounts.insert(accountId)
                }

            case .internalTransfer:
                if let sourceId = transaction.accountId {
                    allAffectedAccounts.insert(sourceId)
                }
                if let targetId = transaction.targetAccountId {
                    allAffectedAccounts.insert(targetId)
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                if let accountId = transaction.accountId {
                    allAffectedAccounts.insert(accountId)
                }
            }
        }

        // Create batch update request
        let request = BalanceQueueRequest(
            accountIds: allAffectedAccounts,
            operation: .recalculateAccounts(allAffectedAccounts),
            priority: priority
        )

        await queue.enqueue(request)

        #if DEBUG
        print("📨 Queued batch update: \(transactions.count) transactions, \(allAffectedAccounts.count) accounts affected")
        #endif
    }

    // MARK: - Account Updates

    func updateForAccount(
        _ account: Account,
        newBalance: Double
    ) async {
        store.setBalance(newBalance, for: account.id, source: .manual)
        cache.setBalance(newBalance, for: account.id)

        #if DEBUG
        print("💰 Updated account balance: \(account.id) = \(newBalance)")
        #endif
    }

    func updateDepositInfo(
        _ account: Account,
        depositInfo: DepositInfo
    ) async {
        store.updateDepositInfo(depositInfo, for: account.id)
        cache.invalidate(accountId: account.id)

        #if DEBUG
        print("🏦 Updated deposit info: \(account.id)")
        #endif
    }

    // MARK: - Recalculation

    func recalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        let request = BalanceQueueRequest(
            accountIds: Set(accounts.map { $0.id }),
            operation: .recalculateAll,
            priority: .normal
        )

        await queue.enqueue(request)
        await processRecalculateAll(accounts: accounts, transactions: transactions)

        #if DEBUG
        print("🔄 Recalculated all balances: \(accounts.count) accounts")
        #endif
    }

    func recalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        let request = BalanceQueueRequest(
            accountIds: accountIds,
            operation: .recalculateAccounts(accountIds),
            priority: .high
        )

        await queue.enqueue(request)
        await processRecalculateAccounts(accountIds, accounts: accounts, transactions: transactions)

        #if DEBUG
        print("🔄 Recalculated \(accountIds.count) accounts")
        #endif
    }

    // MARK: - Optimistic Updates

    func optimisticUpdate(
        accountId: String,
        delta: Double
    ) async -> UUID {
        let operationId = UUID()

        guard let currentBalance = store.getBalance(for: accountId) else {
            return operationId
        }

        let newBalance = currentBalance + delta

        // Apply optimistic update immediately
        store.setBalance(newBalance, for: accountId, source: .manual)

        // Track for potential revert
        let update = OptimisticUpdate(
            id: operationId,
            accountId: accountId,
            previousBalance: currentBalance,
            delta: delta,
            timestamp: Date()
        )
        optimisticUpdates[operationId] = update

        #if DEBUG
        print("⚡ Optimistic update: \(accountId) \(delta > 0 ? "+" : "")\(delta) → \(newBalance)")
        #endif

        return operationId
    }

    func revertOptimisticUpdate(_ operationId: UUID) async {
        guard let update = optimisticUpdates.removeValue(forKey: operationId) else {
            return
        }

        store.setBalance(update.previousBalance, for: update.accountId, source: .manual)

        #if DEBUG
        print("↩️ Reverted optimistic update: \(update.accountId) → \(update.previousBalance)")
        #endif
    }

    // MARK: - Calculation Modes

    func markAsImported(_ accountId: String) async {
        store.markAsImported(accountId)

        #if DEBUG
        print("📥 Marked as imported: \(accountId)")
        #endif
    }

    func markAsManual(_ accountId: String) async {
        store.markAsManual(accountId)

        #if DEBUG
        print("✏️ Marked as manual: \(accountId)")
        #endif
    }

    func setInitialBalance(_ balance: Double, for accountId: String) async {
        store.setInitialBalance(balance, for: accountId)

        #if DEBUG
        print("🏦 Set initial balance: \(accountId) = \(balance)")
        #endif
    }

    func getInitialBalance(for accountId: String) async -> Double? {
        return store.getInitialBalance(for: accountId)
    }

    // MARK: - Cache Management

    func invalidateCache(for accountIds: Set<String>) async {
        cache.invalidate(accountIds: accountIds)
    }

    func invalidateAllCaches() async {
        cache.invalidateAll()
    }

    // MARK: - Queue Management

    func flushQueue() async {
        await queue.flush()
    }

    func cancelPendingUpdates() async {
        await queue.cancelAll()
    }

    // MARK: - Statistics

    func getStatistics() async -> BalanceCoordinatorStatistics {
        let cacheStats = cache.getStatistics()
        let queueStats = await queue.getStatistics()

        return BalanceCoordinatorStatistics(
            cacheStatistics: cacheStats,
            queueStatistics: queueStats,
            totalAccounts: store.getAllAccounts().count,
            lastUpdateTime: lastUpdateTime
        )
    }

    // MARK: - Private Processing

    /// Process update request (called by queue or immediately)
    private func processUpdateRequest(_ request: BalanceQueueRequest) async {
        switch request.operation {
        case .transaction(let txOperation):
            await processTransactionUpdate(txOperation, affectedAccounts: request.accountIds)

        case .recalculateAll:
            // Will be called with full accounts/transactions from public API
            break

        case .recalculateAccounts(let accountIds):
            // Will be called with full accounts/transactions from public API
            break
        }

        lastUpdateTime = Date()
    }

    /// Process transaction update
    private func processTransactionUpdate(
        _ operation: TransactionUpdateOperation,
        affectedAccounts: Set<String>
    ) async {
        // Check cache first
        var accountsToRecalculate = Set<String>()

        for accountId in affectedAccounts {
            if cache.getBalance(for: accountId) == nil {
                accountsToRecalculate.insert(accountId)
            }
        }

        // Apply incremental update if possible
        switch operation {
        case .add(let transaction):
            await processAddTransaction(transaction)

        case .remove(let transaction):
            await processRemoveTransaction(transaction)

        case .update(let oldTx, let newTx):
            await processUpdateTransaction(old: oldTx, new: newTx)
        }

        // Invalidate affected accounts
        cache.invalidate(accountIds: affectedAccounts)
    }

    /// Process add transaction
    private func processAddTransaction(_ transaction: Transaction) async {
        guard let accountId = transaction.accountId,
              var account = store.getAccount(accountId) else {
            return
        }

        let currentBalance = account.currentBalance
        let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: account)

        store.setBalance(newBalance, for: accountId, source: .transaction(transaction.id))
    }

    /// Process remove transaction
    private func processRemoveTransaction(_ transaction: Transaction) async {
        guard let accountId = transaction.accountId,
              var account = store.getAccount(accountId) else {
            return
        }

        let currentBalance = account.currentBalance
        let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: account)

        store.setBalance(newBalance, for: accountId, source: .recalculation)
    }

    /// Process update transaction
    private func processUpdateTransaction(old: Transaction, new: Transaction) async {
        // Revert old, apply new
        await processRemoveTransaction(old)
        await processAddTransaction(new)
    }

    /// Process full recalculation for all accounts
    private func processRecalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        var newBalances: [String: Double] = [:]

        for account in accounts {
            let accountBalance = AccountBalance.from(account)
            let mode = store.getCalculationMode(for: account.id)

            let calculatedBalance = engine.calculateBalance(
                account: accountBalance,
                transactions: transactions,
                mode: mode
            )

            newBalances[account.id] = calculatedBalance
        }

        store.updateBalances(newBalances, source: .recalculation)
        cache.setBalances(newBalances)
    }

    /// Process recalculation for specific accounts
    private func processRecalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        var newBalances: [String: Double] = [:]

        for accountId in accountIds {
            guard let account = accounts.first(where: { $0.id == accountId }) else {
                continue
            }

            let accountBalance = AccountBalance.from(account)
            let mode = store.getCalculationMode(for: account.id)

            let calculatedBalance = engine.calculateBalance(
                account: accountBalance,
                transactions: transactions,
                mode: mode
            )

            newBalances[account.id] = calculatedBalance
        }

        store.updateBalances(newBalances, source: .recalculation)
        cache.setBalances(newBalances)
    }
}

// MARK: - Optimistic Update

/// Represents an optimistic balance update
private struct OptimisticUpdate {
    let id: UUID
    let accountId: String
    let previousBalance: Double
    let delta: Double
    let timestamp: Date
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceCoordinator {
    /// Print current state for debugging
    func debugPrintState() async {
        print("====== BalanceCoordinator State ======")
        print("Balances: \(balances.count)")
        print("Optimistic Updates: \(optimisticUpdates.count)")
        print("Last Update: \(lastUpdateTime?.description ?? "Never")")
        print("======================================")

        let stats = await getStatistics()
        print("\nCache Stats:")
        print("  Entries: \(stats.cacheStatistics.totalEntries)")
        print("  Hit Rate: \(Int(stats.cacheStatistics.hitRate * 100))%")

        print("\nQueue Stats:")
        print("  Pending: \(stats.queueStatistics.pendingCount)")
        print("  Processed: \(stats.queueStatistics.totalProcessed)")
    }
}
#endif
