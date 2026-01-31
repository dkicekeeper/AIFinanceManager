//
//  TransactionBalanceCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-01-31
//

import Foundation

/// Service responsible for coordinating balance calculations between accounts and transactions
/// Extracted from TransactionsViewModel to eliminate duplication and follow SRP
/// This is the SINGLE source of truth for balance calculation logic
@MainActor
class TransactionBalanceCoordinator: TransactionBalanceCoordinatorProtocol {

    // MARK: - Dependencies

    private weak var delegate: TransactionBalanceDelegate?
    private static var dateFormatter: DateFormatter {
        DateFormatters.dateFormatter
    }

    // MARK: - Initialization

    init(delegate: TransactionBalanceDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Public API

    func recalculateAllBalances() {
        guard let delegate = delegate else { return }

        print("💰 [TransactionBalanceCoordinator] STARTING - accounts count: \(delegate.accounts.count), transactions count: \(delegate.allTransactions.count)")
        guard !delegate.accounts.isEmpty else {
            print("💰 [TransactionBalanceCoordinator] SKIPPED - no accounts")
            return
        }

        // OPTIMIZATION: Skip recalculation if nothing changed since last calculation
        if !delegate.cacheManager.balanceCacheInvalidated &&
           delegate.cacheManager.lastBalanceCalculationTransactionCount == delegate.allTransactions.count {
            return
        }

        delegate.currencyConversionWarning = nil
        var balanceChanges: [String: Double] = [:]

        // OPTIMIZATION: Create Set for O(1) account existence checks
        let existingAccountIds = Set(delegate.accounts.map { $0.id })

        // OPTIMIZATION: Create Dictionary for O(1) account lookups
        // For 10,000 transactions × 25 accounts: 250,000 lookups → 5-10x faster
        let accountsById = Dictionary(uniqueKeysWithValues: delegate.accounts.map { ($0.id, $0) })

        // Calculate initialBalance for NEW accounts
        for account in delegate.accounts {
            balanceChanges[account.id] = 0
            if delegate.initialAccountBalances[account.id] == nil {
                // Check if account has manual initial balance from AccountBalanceService
                if let manualInitialBalance = delegate.accountBalanceService.getInitialBalance(for: account.id) {
                    // Manually created account - use its initial balance
                    // DO NOT add to accountsWithCalculatedInitialBalance - transactions MUST be processed!
                    delegate.initialAccountBalances[account.id] = manualInitialBalance

                    // Sync with BalanceCalculationService - mark as manual
                    delegate.balanceCalculationService.markAsManual(account.id)
                    delegate.balanceCalculationService.setInitialBalance(manualInitialBalance, for: account.id)
                } else {
                    // Check if there are transactions for this account
                    let transactionsSum = calculateTransactionsBalance(for: account.id)

                    // CRITICAL: Distinguish two scenarios:
                    // 1. Account created during CSV import with balance=0 - transactions MUST be applied
                    // 2. Account imported with existing balance>0 - transactions already included

                    if account.balance == 0 && transactionsSum != 0 {
                        // Scenario 1: New account created during CSV import
                        // Initial balance = 0, transactions should be applied to calculate balance
                        delegate.initialAccountBalances[account.id] = 0
                        // DO NOT add to accountsWithCalculatedInitialBalance - transactions MUST be processed!

                        // Sync with BalanceCalculationService - mark as manual (transactions applied)
                        delegate.balanceCalculationService.markAsManual(account.id)
                        delegate.balanceCalculationService.setInitialBalance(0, for: account.id)
                    } else {
                        // Scenario 2: Account with existing balance (imported with data)
                        // Calculate initialBalance = balance - transactions
                        // Transactions ALREADY INCLUDED in current balance
                        let initialBalance = account.balance - transactionsSum
                        delegate.initialAccountBalances[account.id] = initialBalance
                        delegate.accountsWithCalculatedInitialBalance.insert(account.id)

                        // Sync with BalanceCalculationService
                        delegate.balanceCalculationService.markAsImported(account.id)
                        delegate.balanceCalculationService.setInitialBalance(initialBalance, for: account.id)
                    }
                }
            }
        }

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter

        // Process all transactions to calculate balance changes
        for tx in delegate.allTransactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if let accountId = tx.accountId,
                   existingAccountIds.contains(accountId),
                   !delegate.accountsWithCalculatedInitialBalance.contains(accountId) {
                    // Use targetAmount if transaction currency differs from account currency
                    let amountToUse: Double
                    if let targetAmount = tx.targetAmount,
                       let targetCurrency = tx.targetCurrency,
                       let account = accountsById[accountId],
                       targetCurrency == account.currency {
                        amountToUse = targetAmount
                    } else {
                        amountToUse = tx.amount
                    }
                    balanceChanges[accountId, default: 0] += amountToUse
                }

            case .expense:
                if let accountId = tx.accountId,
                   existingAccountIds.contains(accountId),
                   !delegate.accountsWithCalculatedInitialBalance.contains(accountId) {
                    // Use targetAmount if transaction currency differs from account currency
                    let amountToUse: Double
                    if let targetAmount = tx.targetAmount,
                       let targetCurrency = tx.targetCurrency,
                       let account = accountsById[accountId],
                       targetCurrency == account.currency {
                        amountToUse = targetAmount
                    } else {
                        amountToUse = tx.amount
                    }
                    balanceChanges[accountId, default: 0] -= amountToUse
                }

            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break

            case .internalTransfer:
                // CRITICAL FIX: Process transfers even if one account is deleted
                // If account deleted WITHOUT transactions, we still need to update the OTHER account's balance

                if let sourceId = tx.accountId {
                    // Only update source if it exists AND needs recalculation
                    if existingAccountIds.contains(sourceId) &&
                       !delegate.accountsWithCalculatedInitialBalance.contains(sourceId) {
                        let sourceAmount = tx.convertedAmount ?? tx.amount
                        balanceChanges[sourceId, default: 0] -= sourceAmount
                    }
                }

                if let targetId = tx.targetAccountId {
                    // Only update target if it exists AND needs recalculation
                    if existingAccountIds.contains(targetId) &&
                       !delegate.accountsWithCalculatedInitialBalance.contains(targetId) {
                        let resolvedTargetAmount = tx.targetAmount ?? tx.convertedAmount ?? tx.amount
                        balanceChanges[targetId, default: 0] += resolvedTargetAmount
                    }
                }
            }
        }

        // Remove orphaned balance changes for non-existent accounts
        balanceChanges = balanceChanges.filter { accountId, _ in
            existingAccountIds.contains(accountId)
        }

        // Create new array instead of modifying elements in place
        // This is necessary for @Published property wrapper to trigger
        var newAccounts = delegate.accounts

        for index in newAccounts.indices {
            let accountId = newAccounts[index].id

            if newAccounts[index].isDeposit {
                if let depositInfo = newAccounts[index].depositInfo {
                    var totalBalance: Decimal = depositInfo.principalBalance
                    if !depositInfo.capitalizationEnabled {
                        totalBalance += depositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[index].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                }
            } else {
                let initialBalance = delegate.initialAccountBalances[accountId] ?? newAccounts[index].balance
                let changes = balanceChanges[accountId] ?? 0
                newAccounts[index].balance = initialBalance + changes
            }
        }

        // Reassign entire array to trigger @Published
        delegate.accounts = newAccounts

        // Sync updated balances with AccountBalanceService
        delegate.accountBalanceService.syncAccountBalances(newAccounts)

        // Save updated balances to Core Data
        delegate.accountBalanceService.saveAllAccountsSync()

        // OPTIMIZATION: Update cache state after successful calculation
        delegate.cacheManager.balanceCacheInvalidated = false
        delegate.cacheManager.lastBalanceCalculationTransactionCount = delegate.allTransactions.count
        delegate.cacheManager.cachedAccountBalances = balanceChanges

        print("💰 [TransactionBalanceCoordinator] COMPLETED - Final balances:")
        for account in delegate.accounts {
            print("💰   Account '\(account.name)': balance = \(account.balance)")
        }
    }

    func applyTransactionDirectly(_ transaction: Transaction) {
        guard let delegate = delegate else { return }

        var newAccounts = delegate.accounts
        var balanceChanged = false

        switch transaction.type {
        case .income:
            if let accountId = transaction.accountId,
               delegate.accountsWithCalculatedInitialBalance.contains(accountId),
               let index = newAccounts.firstIndex(where: { $0.id == accountId }) {
                // Use targetAmount if transaction currency differs from account currency
                let amount: Double
                if let targetAmount = transaction.targetAmount,
                   let targetCurrency = transaction.targetCurrency,
                   targetCurrency == newAccounts[index].currency {
                    amount = targetAmount
                } else {
                    amount = transaction.amount
                }
                newAccounts[index].balance += amount
                balanceChanged = true
            }

        case .expense:
            if let accountId = transaction.accountId,
               delegate.accountsWithCalculatedInitialBalance.contains(accountId),
               let index = newAccounts.firstIndex(where: { $0.id == accountId }) {
                // Use targetAmount if transaction currency differs from account currency
                let amount: Double
                if let targetAmount = transaction.targetAmount,
                   let targetCurrency = transaction.targetCurrency,
                   targetCurrency == newAccounts[index].currency {
                    amount = targetAmount
                } else {
                    amount = transaction.amount
                }
                newAccounts[index].balance -= amount
                balanceChanged = true
            }

        case .internalTransfer:
            // Debit from source account
            if let sourceId = transaction.accountId,
               let sourceIndex = newAccounts.firstIndex(where: { $0.id == sourceId }) {
                let sourceAccount = newAccounts[sourceIndex]
                // Source: use convertedAmount recorded at creation
                let sourceAmount = transaction.convertedAmount ?? transaction.amount

                if sourceAccount.isDeposit, var sourceDepositInfo = sourceAccount.depositInfo {
                    let amountDecimal = Decimal(sourceAmount)
                    if !sourceDepositInfo.capitalizationEnabled && sourceDepositInfo.interestAccruedNotCapitalized > 0 {
                        if amountDecimal <= sourceDepositInfo.interestAccruedNotCapitalized {
                            sourceDepositInfo.interestAccruedNotCapitalized -= amountDecimal
                        } else {
                            let remaining = amountDecimal - sourceDepositInfo.interestAccruedNotCapitalized
                            sourceDepositInfo.interestAccruedNotCapitalized = 0
                            sourceDepositInfo.principalBalance -= remaining
                        }
                    } else {
                        sourceDepositInfo.principalBalance -= amountDecimal
                    }
                    newAccounts[sourceIndex].depositInfo = sourceDepositInfo
                    var totalBalance: Decimal = sourceDepositInfo.principalBalance
                    if !sourceDepositInfo.capitalizationEnabled {
                        totalBalance += sourceDepositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[sourceIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                    balanceChanged = true
                } else if delegate.accountsWithCalculatedInitialBalance.contains(sourceId) {
                    newAccounts[sourceIndex].balance -= sourceAmount
                    balanceChanged = true
                }
            }

            // Credit to target account
            if let targetId = transaction.targetAccountId,
               let targetIndex = newAccounts.firstIndex(where: { $0.id == targetId }) {
                let targetAccount = newAccounts[targetIndex]
                // Target: use targetAmount recorded at creation
                let targetAmount = transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount

                // Handle deposits separately - need to update depositInfo
                if targetAccount.isDeposit, var targetDepositInfo = targetAccount.depositInfo {
                    let amountDecimal = Decimal(targetAmount)
                    targetDepositInfo.principalBalance += amountDecimal
                    newAccounts[targetIndex].depositInfo = targetDepositInfo
                    var totalBalance: Decimal = targetDepositInfo.principalBalance
                    if !targetDepositInfo.capitalizationEnabled {
                        totalBalance += targetDepositInfo.interestAccruedNotCapitalized
                    }
                    newAccounts[targetIndex].balance = NSDecimalNumber(decimal: totalBalance).doubleValue
                    balanceChanged = true
                } else if delegate.accountsWithCalculatedInitialBalance.contains(targetId) {
                    // Regular imported account
                    newAccounts[targetIndex].balance += targetAmount
                    balanceChanged = true
                }
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            // These types are handled through specialized deposit methods
            break
        }

        if balanceChanged {
            delegate.accounts = newAccounts
            // Sync with AccountsViewModel
            delegate.accountBalanceService.syncAccountBalances(newAccounts)
        }
    }

    func scheduleRecalculation() {
        guard let delegate = delegate else { return }

        if delegate.isBatchMode {
            delegate.pendingBalanceRecalculation = true
        } else {
            recalculateAllBalances()
        }
    }

    // MARK: - Helper Methods

    /// Calculate the balance change for a specific account from all transactions
    /// This is used to determine the initial balance (starting capital) of an account
    private func calculateTransactionsBalance(for accountId: String) -> Double {
        guard let delegate = delegate else { return 0 }

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter
        var balance: Double = 0

        for tx in delegate.allTransactions {
            guard let transactionDate = dateFormatter.date(from: tx.date),
                  transactionDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance += amountToUse
                }
            case .expense:
                if tx.accountId == accountId {
                    let amountToUse = tx.convertedAmount ?? tx.amount
                    balance -= amountToUse
                }
            case .internalTransfer:
                if tx.accountId == accountId {
                    // Source: use convertedAmount
                    balance -= tx.convertedAmount ?? tx.amount
                } else if tx.targetAccountId == accountId {
                    // Target: use targetAmount
                    balance += tx.targetAmount ?? tx.convertedAmount ?? tx.amount
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Skip deposit transactions for regular accounts
                break
            }
        }

        return balance
    }
}
