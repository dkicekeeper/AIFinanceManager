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
    /// Handles currency conversion, deposit logic, and transaction creation
    /// - Parameters:
    ///   - sourceId: Source account ID
    ///   - targetId: Target account ID
    ///   - amount: Amount to transfer (in source account currency)
    ///   - currency: Currency of the amount
    ///   - date: Transaction date (ISO8601 string)
    ///   - description: Transaction description
    ///   - accounts: Array of all accounts (will be modified)
    ///   - allTransactions: Array of all transactions (will be modified)
    ///   - accountBalanceService: Service for syncing balances
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
        accountBalanceService: AccountBalanceServiceProtocol,
        saveCallback: () -> Void
    )

    /// Deduct amount from account balance
    /// Handles deposit logic (principal vs interest)
    /// - Parameters:
    ///   - account: Account to deduct from (will be modified)
    ///   - amount: Amount to deduct
    func deduct(
        from account: inout Account,
        amount: Double
    )

    /// Add amount to account balance
    /// Handles deposit logic (adds to principal)
    /// - Parameters:
    ///   - account: Account to add to (will be modified)
    ///   - amount: Amount to add
    func add(
        to account: inout Account,
        amount: Double
    )

    /// Convert amount between currencies if needed
    /// - Parameters:
    ///   - amount: Amount to convert
    ///   - fromCurrency: Source currency
    ///   - toCurrency: Target currency
    /// - Returns: Converted amount (or original if currencies match or conversion fails)
    func convertCurrency(
        amount: Double,
        from fromCurrency: String,
        to toCurrency: String
    ) -> Double
}
