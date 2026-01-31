//
//  TransactionBalanceCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Protocol for coordinating balance calculations across accounts and transactions
/// Extracted from TransactionsViewModel to follow Single Responsibility Principle
/// and eliminate duplication with AccountsViewModel
@MainActor
protocol TransactionBalanceCoordinatorProtocol {
    /// Recalculate all account balances from transactions
    func recalculateAllBalances()

    /// Apply transaction balance changes directly to accounts
    /// Used for imported accounts and deposits where recalculateAllBalances() would skip transactions
    /// - Parameter transaction: The transaction to apply
    func applyTransactionDirectly(_ transaction: Transaction)

    /// Schedule balance recalculation based on batch mode
    func scheduleRecalculation()

    /// Calculate the balance change for a specific account from all transactions
    /// This is used to determine the initial balance (starting capital) of an account
    /// - Parameter accountId: The account ID to calculate balance for
    /// - Returns: Net balance change from all transactions
    func calculateTransactionsBalance(for accountId: String) -> Double
}

/// Delegate protocol for TransactionBalanceCoordinator to access ViewModel state
@MainActor
protocol TransactionBalanceDelegate: AnyObject {
    // State access
    var allTransactions: [Transaction] { get }
    var accounts: [Account] { get set }
    var appSettings: AppSettings { get }
    var isBatchMode: Bool { get }
    var pendingBalanceRecalculation: Bool { get set }

    // Internal state (balance tracking)
    var initialAccountBalances: [String: Double] { get set }
    var accountsWithCalculatedInitialBalance: Set<String> { get set }
    var currencyConversionWarning: String? { get set }

    // Dependencies
    var balanceCalculationService: BalanceCalculationServiceProtocol { get }
    var accountBalanceService: AccountBalanceServiceProtocol { get }
    var cacheManager: TransactionCacheManager { get }
}
