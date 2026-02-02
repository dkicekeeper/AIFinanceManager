//
//  BalanceCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 4
//
//  Protocol for balance coordination
//  Single entry point for all balance operations
//

import Foundation
import Combine

// MARK: - Balance Coordinator Protocol

/// Protocol for coordinating balance calculations and updates
/// Provides a unified interface for balance management across the app
@MainActor
protocol BalanceCoordinatorProtocol: ObservableObject {

    // MARK: - Published State

    /// Current balances for all accounts
    /// UI components observe this for real-time updates
    var balances: [String: Double] { get }

    // MARK: - Account Management

    /// Register accounts with the coordinator
    /// - Parameter accounts: Array of accounts to register
    func registerAccounts(_ accounts: [Account]) async

    /// Remove account from coordinator
    /// - Parameter accountId: Account ID to remove
    func removeAccount(_ accountId: String) async

    // MARK: - Transaction Updates

    /// Update balances for a transaction operation
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - operation: Operation type (add/remove/update)
    ///   - priority: Update priority
    func updateForTransaction(
        _ transaction: Transaction,
        operation: TransactionUpdateOperation,
        priority: BalanceQueueRequest.Priority
    ) async

    /// Update balances for multiple transactions (batch)
    /// - Parameters:
    ///   - transactions: Array of transactions
    ///   - operation: Operation type
    ///   - priority: Update priority
    func updateForTransactions(
        _ transactions: [Transaction],
        operation: TransactionUpdateOperation,
        priority: BalanceQueueRequest.Priority
    ) async

    // MARK: - Account Updates

    /// Update balance for account directly
    /// - Parameters:
    ///   - account: The account
    ///   - newBalance: New balance value
    func updateForAccount(
        _ account: Account,
        newBalance: Double
    ) async

    /// Update deposit info for account
    /// - Parameters:
    ///   - account: The account
    ///   - depositInfo: Updated deposit info
    func updateDepositInfo(
        _ account: Account,
        depositInfo: DepositInfo
    ) async

    // MARK: - Recalculation

    /// Recalculate all balances from scratch
    /// - Parameters:
    ///   - accounts: All accounts
    ///   - transactions: All transactions
    func recalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async

    /// Recalculate balances for specific accounts
    /// - Parameters:
    ///   - accountIds: Set of account IDs to recalculate
    ///   - accounts: All accounts
    ///   - transactions: All transactions
    func recalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async

    // MARK: - Optimistic Updates

    /// Apply optimistic update (instant UI feedback)
    /// - Parameters:
    ///   - accountId: Account ID
    ///   - delta: Balance change amount
    /// - Returns: Operation ID for potential revert
    func optimisticUpdate(
        accountId: String,
        delta: Double
    ) async -> UUID

    /// Revert optimistic update
    /// - Parameter operationId: Operation ID from optimisticUpdate
    func revertOptimisticUpdate(_ operationId: UUID) async

    // MARK: - Calculation Modes

    /// Mark account as imported (transactions already in balance)
    /// - Parameter accountId: Account ID
    func markAsImported(_ accountId: String) async

    /// Mark account as manual (transactions need to be applied)
    /// - Parameter accountId: Account ID
    func markAsManual(_ accountId: String) async

    /// Set initial balance for account
    /// - Parameters:
    ///   - balance: Initial balance
    ///   - accountId: Account ID
    func setInitialBalance(_ balance: Double, for accountId: String) async

    /// Get initial balance for account
    /// - Parameter accountId: Account ID
    /// - Returns: Initial balance if set
    func getInitialBalance(for accountId: String) async -> Double?

    // MARK: - Cache Management

    /// Invalidate cache for specific accounts
    /// - Parameter accountIds: Set of account IDs
    func invalidateCache(for accountIds: Set<String>) async

    /// Invalidate all caches
    func invalidateAllCaches() async

    // MARK: - Queue Management

    /// Flush update queue (force immediate processing)
    func flushQueue() async

    /// Cancel all pending updates
    func cancelPendingUpdates() async

    // MARK: - Statistics

    /// Get coordinator statistics
    /// - Returns: Performance and cache statistics
    func getStatistics() async -> BalanceCoordinatorStatistics
}

// MARK: - Balance Coordinator Statistics

struct BalanceCoordinatorStatistics {
    let cacheStatistics: CacheStatistics
    let queueStatistics: QueueStatistics
    let totalAccounts: Int
    let lastUpdateTime: Date?
}

// MARK: - Default Implementations

extension BalanceCoordinatorProtocol {
    /// Update for transaction with default priority
    func updateForTransaction(_ transaction: Transaction, operation: TransactionUpdateOperation) async {
        await updateForTransaction(transaction, operation: operation, priority: .high)
    }

    /// Update for transactions with default priority
    func updateForTransactions(_ transactions: [Transaction], operation: TransactionUpdateOperation) async {
        await updateForTransactions(transactions, operation: operation, priority: .normal)
    }
}
