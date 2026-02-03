//
//  AccountOperationServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Protocol for account operations (transfers, deposits, withdrawals)
/// Extracted from TransactionsViewModel to follow SRP
@MainActor
protocol AccountOperationServiceProtocol {

    /// Execute transfer between two accounts
    /// Handles currency conversion and transaction creation
    /// Balance updates are delegated to BalanceCoordinator (Single Source of Truth)
    /// - Parameters:
    ///   - sourceId: Source account ID
    ///   - targetId: Target account ID
    ///   - amount: Amount to transfer (in source account currency)
    ///   - currency: Currency of the amount
    ///   - date: Transaction date (ISO8601 string)
    ///   - description: Transaction description
    ///   - accounts: Array of all accounts (for metadata only, not modified)
    ///   - allTransactions: Array of all transactions (will be modified)
    ///   - balanceCoordinator: Coordinator for balance updates (Single Source of Truth)
    ///   - saveCallback: Callback to trigger save operation
    func transfer(
        from sourceId: String,
        to targetId: String,
        amount: Double,
        currency: String,
        date: String,
        description: String,
        accounts: inout [Account],
        allTransactions: inout [Transaction],
        balanceCoordinator: (any BalanceCoordinatorProtocol)?,
        saveCallback: () -> Void
    )

}
