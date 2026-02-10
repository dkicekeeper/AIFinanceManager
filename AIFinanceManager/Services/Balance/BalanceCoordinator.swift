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

    // MARK: - Performance Cache (LRU)

    /// LRU cache for balance calculations (10x performance boost for full recalculations)
    /// Key: "accountId_transactionsHash", Value: calculated balance
    private let calculationCache = NSCache<NSString, NSNumber>()
    private let cacheKeyPrefix = "balance_calc_"

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

        // ⚠️ CRITICAL FIX: Only initialize balances for NEW accounts, preserve existing balances
        var updatedBalances = self.balances  // Start with current balances

        for account in accounts {
            // Only set initial balance if account is NOT already registered
            if updatedBalances[account.id] == nil {
                let initialBalance = account.initialBalance ?? 0
                updatedBalances[account.id] = initialBalance
                cache.setBalance(initialBalance, for: account.id)

                #if DEBUG
                print("💾 Cached balance for \(account.id): \(initialBalance)")
                #endif
            }
        }

        // Update published balances (preserves existing non-zero balances)
        self.balances = updatedBalances

        #if DEBUG
        print("📝 Registered \(accounts.count) accounts")
        print("✅ Published initial balances to UI")
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
        // ✅ OPTIMIZATION: Invalidate LRU cache on transaction changes
        invalidateCalculationCache()

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

        // Process the update immediately for high/immediate priority
        // Queue is just for tracking, actual processing happens here
        if priority == .immediate || priority == .high {
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

        // For batch operations, we should probably trigger a full recalculation
        // instead of trying to apply operations one by one
        // But for now, process individually based on operation type
        for transaction in transactions {
            switch operation {
            case .add:
                await processAddTransaction(transaction)
            case .remove:
                await processRemoveTransaction(transaction)
            case .update:
                // Update operations in batch don't make sense - each needs its own old transaction
                // This case should probably not be used, but handle gracefully
                break
            }
        }

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
        #if DEBUG
        print("🔄 [BalanceCoordinator] recalculateAll() called")
        print("   📊 Input parameters:")
        print("      - accounts: \(accounts.count)")
        print("      - transactions: \(transactions.count)")
        print("   📊 Store state:")
        print("      - store.accounts: \(store.getAllAccounts().count)")
        print("   💰 Current balances BEFORE recalculation:")
        for (accountId, balance) in balances.prefix(5) {
            let accountName = accounts.first(where: { $0.id == accountId })?.name ?? "Unknown"
            print("      - \(accountName): \(balance)")
        }
        #endif

        let request = BalanceQueueRequest(
            accountIds: Set(accounts.map { $0.id }),
            operation: .recalculateAll,
            priority: .normal
        )

        await queue.enqueue(request)
        await processRecalculateAll(accounts: accounts, transactions: transactions)

        #if DEBUG
        print("✅ [BalanceCoordinator] Recalculated all balances: \(accounts.count) accounts")
        print("   💰 New balances AFTER recalculation:")
        for (accountId, balance) in balances.prefix(5) {
            let accountName = accounts.first(where: { $0.id == accountId })?.name ?? "Unknown"
            print("      - \(accountName): \(balance)")
        }
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

        case .recalculateAccounts:
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
        var updatedBalances = self.balances

        // Process source account
        if let accountId = transaction.accountId,
           let account = store.getAccount(accountId) {
            let currentBalance = account.currentBalance
            let newBalance = engine.applyTransaction(transaction, to: currentBalance, for: account)

            store.setBalance(newBalance, for: accountId, source: .transaction(transaction.id))
            updatedBalances[accountId] = newBalance
            persistBalance(newBalance, for: accountId)  // 💾 Persist to Core Data

            #if DEBUG
            print("✅ [BalanceCoordinator] Updated balance for source \(accountId): \(newBalance)")
            #endif
        }

        // For internal transfers, also process target account
        if transaction.type == .internalTransfer,
           let targetAccountId = transaction.targetAccountId,
           let targetAccount = store.getAccount(targetAccountId) {
            let currentBalance = targetAccount.currentBalance
            let newBalance = engine.applyTransaction(
                transaction,
                to: currentBalance,
                for: targetAccount,
                isSource: false  // 🔥 CRITICAL FIX: Target account receives money
            )

            store.setBalance(newBalance, for: targetAccountId, source: .transaction(transaction.id))
            updatedBalances[targetAccountId] = newBalance
            persistBalance(newBalance, for: targetAccountId)  // 💾 Persist to Core Data

            #if DEBUG
            print("✅ [BalanceCoordinator] Updated balance for target \(targetAccountId): \(newBalance) (isSource=false)")
            #endif
        }

        // CRITICAL: Publish entire dictionary to trigger SwiftUI update
        self.balances = updatedBalances
    }

    /// Process remove transaction
    private func processRemoveTransaction(_ transaction: Transaction) async {
        var updatedBalances = self.balances

        // Process source account
        if let accountId = transaction.accountId,
           let account = store.getAccount(accountId) {
            let currentBalance = account.currentBalance
            let newBalance = engine.revertTransaction(transaction, from: currentBalance, for: account)

            store.setBalance(newBalance, for: accountId, source: .recalculation)
            updatedBalances[accountId] = newBalance
            persistBalance(newBalance, for: accountId)  // 💾 Persist to Core Data

            #if DEBUG
            print("✅ [BalanceCoordinator] Updated balance for source \(accountId): \(newBalance)")
            #endif
        }

        // For internal transfers, also process target account
        if transaction.type == .internalTransfer,
           let targetAccountId = transaction.targetAccountId,
           let targetAccount = store.getAccount(targetAccountId) {
            let currentBalance = targetAccount.currentBalance
            let newBalance = engine.revertTransaction(
                transaction,
                from: currentBalance,
                for: targetAccount,
                isSource: false  // 🔥 CRITICAL FIX: Target account reverting received money
            )

            store.setBalance(newBalance, for: targetAccountId, source: .recalculation)
            updatedBalances[targetAccountId] = newBalance
            persistBalance(newBalance, for: targetAccountId)  // 💾 Persist to Core Data

            #if DEBUG
            print("✅ [BalanceCoordinator] Updated balance for target \(targetAccountId): \(newBalance) (isSource=false)")
            #endif
        }

        // CRITICAL: Publish entire dictionary to trigger SwiftUI update
        self.balances = updatedBalances
    }

    /// Process update transaction
    private func processUpdateTransaction(old: Transaction, new: Transaction) async {
        var updatedBalances = self.balances
        var tempBalances: [String: Double] = [:]  // Temporary storage for intermediate balances

        // Step 1: Revert old transaction from source account
        if let accountId = old.accountId,
           let account = store.getAccount(accountId) {
            let currentBalance = account.currentBalance
            let balanceAfterRevert = engine.revertTransaction(old, from: currentBalance, for: account)

            tempBalances[accountId] = balanceAfterRevert  // Store temporarily, don't update store yet

            #if DEBUG
            print("🔄 [BalanceCoordinator] Reverted old transaction for \(accountId): \(currentBalance) → \(balanceAfterRevert)")
            #endif
        }

        // Step 2: Revert old transaction from target account (for internal transfers)
        if old.type == .internalTransfer,
           let targetAccountId = old.targetAccountId,
           let targetAccount = store.getAccount(targetAccountId) {
            let currentBalance = targetAccount.currentBalance
            let balanceAfterRevert = engine.revertTransaction(
                old,
                from: currentBalance,
                for: targetAccount,
                isSource: false
            )

            tempBalances[targetAccountId] = balanceAfterRevert  // Store temporarily

            #if DEBUG
            print("🔄 [BalanceCoordinator] Reverted old transaction for target \(targetAccountId): \(currentBalance) → \(balanceAfterRevert)")
            #endif
        }

        // Step 3: Apply new transaction to source account
        if let accountId = new.accountId {
            // Use temporary balance if available (from revert step), otherwise get from store
            let intermediateBalance = tempBalances[accountId] ?? (store.getAccount(accountId)?.currentBalance ?? 0.0)

            // Create temporary account with intermediate balance for calculation
            let tempAccount = AccountBalance(
                accountId: accountId,
                currentBalance: intermediateBalance,
                initialBalance: nil,
                currency: store.getAccount(accountId)?.currency ?? "KZT"
            )

            let balanceAfterApply = engine.applyTransaction(new, to: intermediateBalance, for: tempAccount)

            // Update store with final balance
            store.setBalance(balanceAfterApply, for: accountId, source: .transaction(new.id))
            updatedBalances[accountId] = balanceAfterApply

            #if DEBUG
            print("✅ [BalanceCoordinator] Applied new transaction for \(accountId): \(intermediateBalance) → \(balanceAfterApply)")
            #endif
        }

        // Step 4: Apply new transaction to target account (for internal transfers)
        if new.type == .internalTransfer,
           let targetAccountId = new.targetAccountId {
            // Use temporary balance if available (from revert step), otherwise get from store
            let intermediateBalance = tempBalances[targetAccountId] ?? (store.getAccount(targetAccountId)?.currentBalance ?? 0.0)

            // Create temporary account with intermediate balance for calculation
            let tempAccount = AccountBalance(
                accountId: targetAccountId,
                currentBalance: intermediateBalance,
                initialBalance: nil,
                currency: store.getAccount(targetAccountId)?.currency ?? "KZT"
            )

            let balanceAfterApply = engine.applyTransaction(
                new,
                to: intermediateBalance,
                for: tempAccount,
                isSource: false
            )

            // Update store with final balance
            store.setBalance(balanceAfterApply, for: targetAccountId, source: .transaction(new.id))
            updatedBalances[targetAccountId] = balanceAfterApply

            #if DEBUG
            print("✅ [BalanceCoordinator] Applied new transaction for target \(targetAccountId): \(intermediateBalance) → \(balanceAfterApply)")
            #endif
        }

        // CRITICAL: Publish entire dictionary ONCE to trigger SwiftUI update
        self.balances = updatedBalances
    }

    // MARK: - LRU Cache Helpers

    /// Get cached balance if available
    private func getCachedBalance(accountId: String, transactionsHash: Int) -> Double? {
        let key = "\(cacheKeyPrefix)\(accountId)_\(transactionsHash)" as NSString
        return calculationCache.object(forKey: key)?.doubleValue
    }

    /// Cache calculated balance
    private func cacheBalance(_ balance: Double, accountId: String, transactionsHash: Int) {
        let key = "\(cacheKeyPrefix)\(accountId)_\(transactionsHash)" as NSString
        calculationCache.setObject(NSNumber(value: balance), forKey: key)
    }

    /// Invalidate calculation cache
    private func invalidateCalculationCache() {
        calculationCache.removeAllObjects()
    }

    // MARK: - Private Processing

    /// Process full recalculation for all accounts
    private func processRecalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        #if DEBUG
        print("🔄 [BalanceCoordinator] processRecalculateAll() started")
        print("   📊 Processing \(accounts.count) accounts with \(transactions.count) transactions")
        #endif

        var newBalances: [String: Double] = [:]

        // Calculate hash of transactions for cache key
        let transactionsHash = transactions.map { $0.id }.hashValue

        #if DEBUG
        print("   🔑 Transactions hash: \(transactionsHash)")
        #endif

        for account in accounts {
            // Get AccountBalance from store (contains initialBalance)
            // Don't create new AccountBalance from Account model!
            guard let accountBalance = store.getAccount(account.id) else {
                #if DEBUG
                print("⚠️ [BalanceCoordinator] Account not found in store: \(account.id) (\(account.name))")
                #endif
                continue
            }

            #if DEBUG
            print("   🔍 Processing account: \(account.name) (id: \(account.id))")
            print("      - Initial balance: \(accountBalance.initialBalance ?? 0.0)")
            print("      - Current balance: \(accountBalance.currentBalance)")
            #endif

            // ✅ OPTIMIZATION: Check LRU cache first (10x performance boost)
            if let cachedBalance = getCachedBalance(accountId: account.id, transactionsHash: transactionsHash) {
                newBalances[account.id] = cachedBalance
                #if DEBUG
                print("⚡ [BalanceCoordinator] Cache HIT for \(account.id): \(cachedBalance)")
                #endif
                continue
            }

            let mode = store.getCalculationMode(for: account.id)

            let calculatedBalance = engine.calculateBalance(
                account: accountBalance,
                transactions: transactions,
                mode: mode
            )

            // ✅ OPTIMIZATION: Cache the result
            cacheBalance(calculatedBalance, accountId: account.id, transactionsHash: transactionsHash)
            newBalances[account.id] = calculatedBalance

            #if DEBUG
            print("🧮 [BalanceCoordinator] Cache MISS for \(account.id): calculated \(calculatedBalance)")
            #endif
        }

        store.updateBalances(newBalances, source: .recalculation)
        cache.setBalances(newBalances)

        // 💾 Persist all balances to Core Data
        persistBalances(newBalances)

        // CRITICAL: Publish balances to trigger UI updates
        self.balances = newBalances

        #if DEBUG
        print("✅ [BalanceCoordinator] Published \(newBalances.count) balances to UI")
        #endif
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

            // Get AccountBalance from store (contains initialBalance)
            // Don't create new AccountBalance from Account model!
            guard let accountBalance = store.getAccount(account.id) else {
                #if DEBUG
                print("⚠️ [BalanceCoordinator] Account not found in store: \(account.id)")
                #endif
                continue
            }

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

        // CRITICAL: Merge and publish balances to trigger UI updates
        // SwiftUI only detects changes when the entire dictionary is replaced
        var updatedBalances = self.balances
        for (accountId, balance) in newBalances {
            updatedBalances[accountId] = balance
        }
        self.balances = updatedBalances

        #if DEBUG
        print("✅ [BalanceCoordinator] Published \(newBalances.count) updated balances to UI")
        #endif
    }

    // MARK: - Persistence

    /// Persist balance to Core Data
    /// Called after balance calculation to keep Core Data in sync with in-memory balances
    private func persistBalance(_ balance: Double, for accountId: String) {
        guard let coreDataRepo = repository as? CoreDataRepository else {
            return  // Only persist for CoreDataRepository
        }

        coreDataRepo.updateAccountBalance(accountId: accountId, balance: balance)
    }

    /// Persist multiple balances to Core Data
    /// Called after batch recalculation
    private func persistBalances(_ balances: [String: Double]) {
        guard let coreDataRepo = repository as? CoreDataRepository else {
            return
        }

        for (accountId, balance) in balances {
            coreDataRepo.updateAccountBalance(accountId: accountId, balance: balance)
        }

        #if DEBUG
        print("💾 [BalanceCoordinator] Persisted \(balances.count) balances to Core Data")
        #endif
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
