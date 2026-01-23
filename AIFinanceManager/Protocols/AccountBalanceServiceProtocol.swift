//
//  AccountBalanceServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Protocol for account balance management operations
//  Decouples TransactionsViewModel from AccountsViewModel

import Foundation

/// Protocol for managing account balances
/// Allows TransactionsViewModel to update account balances without tight coupling to AccountsViewModel
protocol AccountBalanceServiceProtocol: AnyObject {
    
    // MARK: - Balance Operations
    
    /// Synchronize account balances with updated data
    /// - Parameter accounts: Updated accounts with new balances
    func syncAccountBalances(_ accounts: [Account])
    
    /// Save all accounts (used after balance recalculation)
    func saveAllAccountsSync()
    
    // MARK: - Account Access
    
    /// Get account by ID
    /// - Parameter id: Account ID
    /// - Returns: Account if found, nil otherwise
    func getAccount(by id: String) -> Account?
    
    /// Get all accounts
    var accounts: [Account] { get }
    
    // MARK: - Initial Balance
    
    /// Get initial balance for account
    /// - Parameter accountId: Account ID
    /// - Returns: Initial balance if set, nil otherwise
    func getInitialBalance(for accountId: String) -> Double?
    
    /// Set initial balance for account
    /// - Parameters:
    ///   - balance: Initial balance value
    ///   - accountId: Account ID
    func setInitialBalance(_ balance: Double, for accountId: String)
}

// MARK: - Default Implementation for Testing

#if DEBUG
/// Mock implementation for testing
class MockAccountBalanceService: AccountBalanceServiceProtocol {
    var accounts: [Account] = []
    private var initialBalances: [String: Double] = [:]
    
    func syncAccountBalances(_ accounts: [Account]) {
        print("🧪 [MOCK] syncAccountBalances called with \(accounts.count) accounts")
        self.accounts = accounts
    }
    
    func saveAllAccountsSync() {
        print("🧪 [MOCK] saveAllAccountsSync called")
    }
    
    func getAccount(by id: String) -> Account? {
        return accounts.first { $0.id == id }
    }
    
    func getInitialBalance(for accountId: String) -> Double? {
        return initialBalances[accountId]
    }
    
    func setInitialBalance(_ balance: Double, for accountId: String) {
        initialBalances[accountId] = balance
    }
}
#endif
