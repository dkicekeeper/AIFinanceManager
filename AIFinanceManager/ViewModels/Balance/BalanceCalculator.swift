//
//  BalanceCalculator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: TransactionsViewModel Decomposition
//

import Foundation

/// Actor responsible for calculating account balances from transactions
/// Extracted from TransactionsViewModel to improve separation of concerns and thread safety
/// Using actor to prevent race conditions during balance calculations
actor BalanceCalculator {

    // MARK: - Properties

    private let dateFormatter: DateFormatter

    // MARK: - Initialization

    init(dateFormatter: DateFormatter) {
        self.dateFormatter = dateFormatter
    }

    // MARK: - Balance Calculation

    /// Calculate balance changes for all accounts from transactions
    /// - Parameters:
    ///   - transactions: Array of all transactions
    ///   - accounts: Array of accounts
    ///   - accountsToSkip: Set of account IDs to skip (e.g., accounts with calculated initial balance)
    ///   - today: The cutoff date for including transactions
    /// - Returns: Dictionary of account ID -> balance change, and flag indicating conversion issues
    func calculateBalanceChanges(
        transactions: [Transaction],
        accounts: [Account],
        accountsToSkip: Set<String>,
        today: Date
    ) async -> (balanceChanges: [String: Double], hasConversionIssues: Bool) {
        var balanceChanges: [String: Double] = [:]
        var hasConversionIssues = false

        // OPTIMIZATION: Create account lookup dictionary for O(1) access
        var accountsDict: [String: Account] = [:]
        for account in accounts {
            accountsDict[account.id] = account
            balanceChanges[account.id] = 0
        }

        // Process each transaction
        for tx in transactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if let accountId = tx.accountId {
                    guard !accountsToSkip.contains(accountId) else { continue }
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] += amountToUse
                }

            case .expense:
                if let accountId = tx.accountId {
                    guard !accountsToSkip.contains(accountId) else { continue }
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balanceChanges[accountId, default: 0] -= amountToUse
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break

            case .internalTransfer:
                // Handle source account
                if let sourceId = tx.accountId,
                   let sourceAccount = accountsDict[sourceId] {
                    guard !accountsToSkip.contains(sourceId) else {
                        // Check if we need to process target account
                        if let targetId = tx.targetAccountId, !accountsToSkip.contains(targetId) {
                            // Process only target below
                        } else {
                            continue
                        }

                        // Process target only
                        if let targetId = tx.targetAccountId,
                           let targetAccount = accountsDict[targetId] {
                            let (targetAmount, conversionFailed) = convertAmount(
                                amount: tx.amount,
                                from: tx.currency,
                                to: targetAccount.currency
                            )
                            if conversionFailed {
                                hasConversionIssues = true
                            }
                            balanceChanges[targetId, default: 0] += targetAmount
                        }
                        continue
                    }

                    // Process source account
                    let sourceAmount: Double
                    if tx.currency == sourceAccount.currency {
                        sourceAmount = tx.amount
                    } else if let converted = tx.convertedAmount {
                        sourceAmount = converted
                    } else {
                        let (amount, conversionFailed) = convertAmount(
                            amount: tx.amount,
                            from: tx.currency,
                            to: sourceAccount.currency
                        )
                        sourceAmount = amount
                        if conversionFailed {
                            hasConversionIssues = true
                        }
                    }
                    balanceChanges[sourceId, default: 0] -= sourceAmount
                }

                // Handle target account
                if let targetId = tx.targetAccountId,
                   let targetAccount = accountsDict[targetId] {
                    guard !accountsToSkip.contains(targetId) else { continue }

                    let (targetAmount, conversionFailed) = convertAmount(
                        amount: tx.amount,
                        from: tx.currency,
                        to: targetAccount.currency
                    )
                    if conversionFailed {
                        hasConversionIssues = true
                    }
                    balanceChanges[targetId, default: 0] += targetAmount
                }
            }
        }

        return (balanceChanges, hasConversionIssues)
    }

    /// Calculate balance for a specific account
    /// - Parameters:
    ///   - accountId: The account ID to calculate balance for
    ///   - transactions: Array of all transactions
    ///   - initialBalance: The initial balance of the account
    ///   - today: The cutoff date for including transactions
    /// - Returns: The calculated balance
    func calculateBalance(
        for accountId: String,
        transactions: [Transaction],
        initialBalance: Double,
        today: Date
    ) async -> Double {
        var balance = initialBalance

        for tx in transactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    balance += tx.convertedAmount ?? tx.amount
                }

            case .expense:
                if tx.accountId == accountId {
                    balance -= tx.convertedAmount ?? tx.amount
                }

            case .internalTransfer:
                if tx.accountId == accountId {
                    balance -= tx.convertedAmount ?? tx.amount
                } else if tx.targetAccountId == accountId {
                    balance += tx.convertedAmount ?? tx.amount
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break
            }
        }

        return balance
    }

    /// Calculate sum of transactions for a specific account (for initial balance calculation)
    /// - Parameters:
    ///   - accountId: The account ID
    ///   - transactions: Array of all transactions
    /// - Returns: The sum of transaction amounts
    func calculateTransactionsSum(
        for accountId: String,
        transactions: [Transaction]
    ) async -> Double {
        var sum: Double = 0

        for tx in transactions {
            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    sum += tx.convertedAmount ?? tx.amount
                }

            case .expense:
                if tx.accountId == accountId {
                    sum -= tx.convertedAmount ?? tx.amount
                }

            case .internalTransfer:
                if tx.accountId == accountId {
                    sum -= tx.convertedAmount ?? tx.amount
                } else if tx.targetAccountId == accountId {
                    sum += tx.convertedAmount ?? tx.amount
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break
            }
        }

        return sum
    }

    // MARK: - Deposit Balance Calculation

    /// Calculate balance for deposit accounts
    /// - Parameters:
    ///   - account: The deposit account
    /// - Returns: The calculated balance
    func calculateDepositBalance(account: Account) -> Double {
        guard let depositInfo = account.depositInfo else {
            return account.balance
        }

        var totalBalance: Decimal = depositInfo.principalBalance
        if !depositInfo.capitalizationEnabled {
            totalBalance += depositInfo.interestAccruedNotCapitalized
        }

        return NSDecimalNumber(decimal: totalBalance).doubleValue
    }

    // MARK: - Private Helpers

    private func convertAmount(amount: Double, from: String, to: String) -> (amount: Double, failed: Bool) {
        if from == to {
            return (amount, false)
        }

        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: to) {
            return (converted, false)
        }

        // Conversion failed - return original amount and flag
        print("⚠️ [BALANCE] Failed to convert \(amount) \(from) to \(to)")
        return (amount, true)
    }
}
