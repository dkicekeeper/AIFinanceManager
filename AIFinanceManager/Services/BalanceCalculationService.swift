//
//  BalanceCalculationService.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//
//  Service for calculating account balances
//  Provides unified balance calculation logic to avoid conflicts between
//  CSV import and manual transaction creation

import Foundation

// MARK: - Balance Calculation Mode

/// Determines how balance should be calculated for an account
enum BalanceCalculationMode {
    /// Manual accounts: balance = initialBalance + Σtransactions
    /// Used for accounts created manually with a specified initial balance
    case fromInitialBalance

    /// Imported accounts: transactions are already factored into current balance
    /// Used for accounts imported from CSV where balance already includes all transactions
    case preserveImported
}

// MARK: - Balance Update

/// Represents a balance update operation
struct BalanceUpdate: Equatable {
    let accountId: String
    let newBalance: Double
    let source: BalanceUpdateSource

    enum BalanceUpdateSource: Equatable {
        case transaction(String)      // Transaction ID
        case recalculation
        case import_
        case manual
    }
}

// MARK: - Protocol

/// Protocol for balance calculation operations
/// Centralizes balance calculation logic to avoid conflicts between different flows
protocol BalanceCalculationServiceProtocol: AnyObject {

    // MARK: - Calculation Mode

    /// Get the calculation mode for an account
    /// - Parameter accountId: Account ID
    /// - Returns: The calculation mode (fromInitialBalance or preserveImported)
    func getCalculationMode(for accountId: String) -> BalanceCalculationMode

    /// Mark an account as imported (transactions already in balance)
    /// - Parameter accountId: Account ID
    func markAsImported(_ accountId: String)

    /// Mark an account as manual (needs transaction application)
    /// - Parameter accountId: Account ID
    func markAsManual(_ accountId: String)

    /// Check if account is imported
    /// - Parameter accountId: Account ID
    /// - Returns: true if account was imported
    func isImported(_ accountId: String) -> Bool

    // MARK: - Initial Balance Management

    /// Get initial balance for account
    /// - Parameter accountId: Account ID
    /// - Returns: Initial balance if set
    func getInitialBalance(for accountId: String) -> Double?

    /// Set initial balance for account
    /// - Parameters:
    ///   - balance: Initial balance
    ///   - accountId: Account ID
    func setInitialBalance(_ balance: Double, for accountId: String)

    /// Calculate initial balance from current balance and transactions
    /// Formula: initialBalance = currentBalance - Σtransactions
    /// - Parameters:
    ///   - currentBalance: Current account balance
    ///   - transactions: All transactions for this account
    ///   - accountCurrency: Account currency for conversion
    /// - Returns: Calculated initial balance
    func calculateInitialBalance(
        currentBalance: Double,
        transactions: [Transaction],
        accountCurrency: String
    ) -> Double

    // MARK: - Balance Calculation

    /// Calculate balance for an account based on its mode
    /// - Parameters:
    ///   - account: The account
    ///   - transactions: All transactions
    ///   - allAccounts: All accounts (for transfer target lookups)
    /// - Returns: Calculated balance
    func calculateBalance(
        for account: Account,
        transactions: [Transaction],
        allAccounts: [Account]
    ) -> Double

    /// Apply a single transaction to a balance
    /// - Parameters:
    ///   - transaction: The transaction to apply
    ///   - currentBalance: Current balance
    ///   - account: The account
    ///   - isSource: true if this is the source account for transfers
    /// - Returns: New balance after applying transaction
    func applyTransaction(
        _ transaction: Transaction,
        to currentBalance: Double,
        for account: Account,
        isSource: Bool
    ) -> Double

    // MARK: - Deposit Handling

    /// Apply transaction to deposit info
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - depositInfo: Current deposit info
    ///   - isSource: true if this is source account for transfer
    /// - Returns: Updated deposit info and new balance
    func applyTransactionToDeposit(
        _ transaction: Transaction,
        depositInfo: DepositInfo,
        isSource: Bool
    ) -> (depositInfo: DepositInfo, balance: Double)

    // MARK: - State Management

    /// Clear all imported account flags
    /// Used when resetting balance calculation state
    func clearImportedFlags()

    /// Clear initial balance for account
    /// - Parameter accountId: Account ID
    func clearInitialBalance(for accountId: String)

    // MARK: - Incremental Updates

    /// Update balance incrementally for a single transaction addition
    /// Much faster than full recalculation (O(1) vs O(n))
    /// - Parameters:
    ///   - transaction: The added transaction
    ///   - accounts: All accounts
    ///   - currentTransactionCount: Current total transaction count
    /// - Returns: Updated balances for affected accounts only
    func updateBalancesForAddedTransaction(
        _ transaction: Transaction,
        accounts: [Account],
        currentTransactionCount: Int
    ) -> [String: Double]

    /// Update balance incrementally for a single transaction removal
    /// - Parameters:
    ///   - transaction: The removed transaction
    ///   - accounts: All accounts
    ///   - currentTransactionCount: Current total transaction count
    /// - Returns: Updated balances for affected accounts only
    func updateBalancesForRemovedTransaction(
        _ transaction: Transaction,
        accounts: [Account],
        currentTransactionCount: Int
    ) -> [String: Double]

    /// Calculate all balances from scratch and cache the result
    /// Use for initial load or when incremental update is not possible
    /// - Parameters:
    ///   - accounts: All accounts
    ///   - transactions: All transactions
    /// - Returns: Dictionary of account balances
    func calculateAndCacheAllBalances(
        accounts: [Account],
        transactions: [Transaction]
    ) -> [String: Double]
}

// MARK: - Implementation

/// Default implementation of balance calculation service
final class BalanceCalculationService: BalanceCalculationServiceProtocol {

    // MARK: - Dependencies

    /// Cache manager for optimized date parsing
    private var cacheManager: TransactionCacheManager?

    // MARK: - State

    /// Set of account IDs that were imported (transactions already in balance)
    private var importedAccountIds: Set<String> = []

    /// Initial balances for accounts
    private var initialBalances: [String: Double] = [:]

    /// Last calculated balances (for incremental updates)
    private var lastCalculatedBalances: [String: Double] = [:]

    /// Transaction count at last full calculation (for detecting batch operations)
    private var lastCalculationTransactionCount: Int = 0

    // MARK: - Initialization

    /// Set cache manager for optimized date parsing
    func setCacheManager(_ cacheManager: TransactionCacheManager) {
        self.cacheManager = cacheManager
    }

    // MARK: - Calculation Mode

    func getCalculationMode(for accountId: String) -> BalanceCalculationMode {
        return importedAccountIds.contains(accountId) ? .preserveImported : .fromInitialBalance
    }

    func markAsImported(_ accountId: String) {
        importedAccountIds.insert(accountId)
    }

    func markAsManual(_ accountId: String) {
        importedAccountIds.remove(accountId)
    }

    func isImported(_ accountId: String) -> Bool {
        return importedAccountIds.contains(accountId)
    }

    // MARK: - Initial Balance Management

    func getInitialBalance(for accountId: String) -> Double? {
        return initialBalances[accountId]
    }

    func setInitialBalance(_ balance: Double, for accountId: String) {
        initialBalances[accountId] = balance
    }

    func calculateInitialBalance(
        currentBalance: Double,
        transactions: [Transaction],
        accountCurrency: String
    ) -> Double {
        var transactionsSum: Double = 0

        for tx in transactions {
            let amount = getTransactionAmount(tx, for: accountCurrency)

            switch tx.type {
            case .income:
                transactionsSum += amount
            case .expense:
                transactionsSum -= amount
            case .internalTransfer:
                // This will be handled by the caller which knows source/target
                break
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Deposits handled separately
                break
            }
        }

        return currentBalance - transactionsSum
    }

    // MARK: - Balance Calculation

    func calculateBalance(
        for account: Account,
        transactions: [Transaction],
        allAccounts: [Account]
    ) -> Double {
        // Deposits have their own balance calculation
        if account.isDeposit, let depositInfo = account.depositInfo {
            var totalBalance: Decimal = depositInfo.principalBalance
            if !depositInfo.capitalizationEnabled {
                totalBalance += depositInfo.interestAccruedNotCapitalized
            }
            return NSDecimalNumber(decimal: totalBalance).doubleValue
        }

        let mode = getCalculationMode(for: account.id)

        switch mode {
        case .preserveImported:
            // For imported accounts, balance is already correct
            // New transactions should be applied via applyTransaction
            return account.balance

        case .fromInitialBalance:
            // Calculate from initial balance + transactions
            guard let initialBalance = getInitialBalance(for: account.id) else {
                // No initial balance set, return current
                return account.balance
            }

            let today = Calendar.current.startOfDay(for: Date())

            var balance = initialBalance

            for tx in transactions {
                // Use cached date parsing if available, otherwise fallback to DateFormatters
                let txDate: Date?
                if let cache = cacheManager {
                    txDate = cache.getParsedDate(for: tx.date)
                } else {
                    txDate = DateFormatters.dateFormatter.date(from: tx.date)
                }

                guard let txDate = txDate, txDate <= today else {
                    continue
                }

                switch tx.type {
                case .income:
                    if tx.accountId == account.id {
                        balance += getTransactionAmount(tx, for: account.currency)
                    }

                case .expense:
                    if tx.accountId == account.id {
                        balance -= getTransactionAmount(tx, for: account.currency)
                    }

                case .internalTransfer:
                    if tx.accountId == account.id {
                        // Source account - subtract
                        balance -= getSourceAmount(tx)
                    } else if tx.targetAccountId == account.id {
                        // Target account - add (используем targetAmount, записанный при создании)
                        balance += getTargetAmount(tx)
                    }

                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    // Handled by deposit-specific logic
                    break
                }
            }

            return balance
        }
    }

    func applyTransaction(
        _ transaction: Transaction,
        to currentBalance: Double,
        for account: Account,
        isSource: Bool
    ) -> Double {
        switch transaction.type {
        case .income:
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .expense:
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .internalTransfer:
            if isSource {
                return currentBalance - getSourceAmount(transaction)
            } else {
                return currentBalance + getTargetAmount(transaction)
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            return currentBalance
        }
    }

    // MARK: - Deposit Handling

    func applyTransactionToDeposit(
        _ transaction: Transaction,
        depositInfo: DepositInfo,
        isSource: Bool
    ) -> (depositInfo: DepositInfo, balance: Double) {
        var updatedInfo = depositInfo
        let amount = Decimal(transaction.amount)

        if isSource {
            // Withdrawing from deposit
            if !updatedInfo.capitalizationEnabled && updatedInfo.interestAccruedNotCapitalized > 0 {
                // First withdraw from accrued interest
                if amount <= updatedInfo.interestAccruedNotCapitalized {
                    updatedInfo.interestAccruedNotCapitalized -= amount
                } else {
                    let remaining = amount - updatedInfo.interestAccruedNotCapitalized
                    updatedInfo.interestAccruedNotCapitalized = 0
                    updatedInfo.principalBalance -= remaining
                }
            } else {
                updatedInfo.principalBalance -= amount
            }
        } else {
            // Adding to deposit
            updatedInfo.principalBalance += amount
        }

        // Calculate total balance
        var totalBalance: Decimal = updatedInfo.principalBalance
        if !updatedInfo.capitalizationEnabled {
            totalBalance += updatedInfo.interestAccruedNotCapitalized
        }

        return (updatedInfo, NSDecimalNumber(decimal: totalBalance).doubleValue)
    }

    // MARK: - State Management

    func clearImportedFlags() {
        importedAccountIds.removeAll()
    }

    func clearInitialBalance(for accountId: String) {
        initialBalances.removeValue(forKey: accountId)
    }

    // MARK: - Incremental Updates

    func updateBalancesForAddedTransaction(
        _ transaction: Transaction,
        accounts: [Account],
        currentTransactionCount: Int
    ) -> [String: Double] {
        // Detect batch operations: если добавилось много транзакций сразу - делаем full recalc
        let transactionDelta = abs(currentTransactionCount - lastCalculationTransactionCount)
        if transactionDelta > 10 {
            // Batch operation detected - force full recalc
            return calculateAndCacheAllBalances(accounts: accounts, transactions: [])
        }

        // Получаем текущие балансы или используем кэш
        var balances = lastCalculatedBalances
        if balances.isEmpty {
            // Кэш пустой - используем текущие балансы счетов
            balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })
        }

        // Применяем транзакцию только к затронутым счетам
        var updatedBalances: [String: Double] = [:]

        switch transaction.type {
        case .income, .expense:
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                let currentBalance = balances[accountId] ?? account.balance
                let newBalance = applyTransaction(transaction, to: currentBalance, for: account, isSource: true)
                balances[accountId] = newBalance
                updatedBalances[accountId] = newBalance
            }

        case .internalTransfer:
            // Обновляем оба счёта
            if let sourceAccountId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceAccountId }) {
                let currentBalance = balances[sourceAccountId] ?? sourceAccount.balance
                let newBalance = applyTransaction(transaction, to: currentBalance, for: sourceAccount, isSource: true)
                balances[sourceAccountId] = newBalance
                updatedBalances[sourceAccountId] = newBalance
            }

            if let targetAccountId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetAccountId }) {
                let currentBalance = balances[targetAccountId] ?? targetAccount.balance
                let newBalance = applyTransaction(transaction, to: currentBalance, for: targetAccount, isSource: false)
                balances[targetAccountId] = newBalance
                updatedBalances[targetAccountId] = newBalance
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            // Deposits handled separately - no incremental update for now
            break
        }

        // Обновляем кэш
        lastCalculatedBalances = balances
        lastCalculationTransactionCount = currentTransactionCount

        return updatedBalances
    }

    func updateBalancesForRemovedTransaction(
        _ transaction: Transaction,
        accounts: [Account],
        currentTransactionCount: Int
    ) -> [String: Double] {
        // Detect batch operations
        let transactionDelta = abs(currentTransactionCount - lastCalculationTransactionCount)
        if transactionDelta > 10 {
            // Batch operation detected - force full recalc
            return calculateAndCacheAllBalances(accounts: accounts, transactions: [])
        }

        // Получаем текущие балансы или используем кэш
        var balances = lastCalculatedBalances
        if balances.isEmpty {
            balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })
        }

        // Откатываем транзакцию (применяем обратную операцию)
        var updatedBalances: [String: Double] = [:]

        switch transaction.type {
        case .income:
            // Откатываем доход - вычитаем
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                let currentBalance = balances[accountId] ?? account.balance
                let amount = getTransactionAmount(transaction, for: account.currency)
                let newBalance = currentBalance - amount
                balances[accountId] = newBalance
                updatedBalances[accountId] = newBalance
            }

        case .expense:
            // Откатываем расход - добавляем
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                let currentBalance = balances[accountId] ?? account.balance
                let amount = getTransactionAmount(transaction, for: account.currency)
                let newBalance = currentBalance + amount
                balances[accountId] = newBalance
                updatedBalances[accountId] = newBalance
            }

        case .internalTransfer:
            // Откатываем перевод
            if let sourceAccountId = transaction.accountId,
               let sourceAccount = accounts.first(where: { $0.id == sourceAccountId }) {
                let currentBalance = balances[sourceAccountId] ?? sourceAccount.balance
                let amount = getSourceAmount(transaction)
                let newBalance = currentBalance + amount // Возвращаем деньги источнику
                balances[sourceAccountId] = newBalance
                updatedBalances[sourceAccountId] = newBalance
            }

            if let targetAccountId = transaction.targetAccountId,
               let targetAccount = accounts.first(where: { $0.id == targetAccountId }) {
                let currentBalance = balances[targetAccountId] ?? targetAccount.balance
                let amount = getTargetAmount(transaction)
                let newBalance = currentBalance - amount // Убираем у получателя
                balances[targetAccountId] = newBalance
                updatedBalances[targetAccountId] = newBalance
            }

        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            // Deposits handled separately
            break
        }

        // Обновляем кэш
        lastCalculatedBalances = balances
        lastCalculationTransactionCount = currentTransactionCount

        return updatedBalances
    }

    func calculateAndCacheAllBalances(
        accounts: [Account],
        transactions: [Transaction]
    ) -> [String: Double] {
        var balances: [String: Double] = [:]

        for account in accounts {
            let balance = calculateBalance(for: account, transactions: transactions, allAccounts: accounts)
            balances[account.id] = balance
        }

        // Кэшируем результат
        lastCalculatedBalances = balances
        lastCalculationTransactionCount = transactions.count

        return balances
    }

    // MARK: - Private Helpers

    /// Сумма транзакции в валюте счёта (для income/expense)
    /// Использует convertedAmount, записанный при создании транзакции
    private func getTransactionAmount(_ transaction: Transaction, for targetCurrency: String) -> Double {
        if transaction.currency == targetCurrency {
            return transaction.amount
        }
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Сумма со стороны источника перевода
    private func getSourceAmount(_ transaction: Transaction) -> Double {
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Сумма со стороны получателя перевода
    private func getTargetAmount(_ transaction: Transaction) -> Double {
        return transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount
    }
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceCalculationService {
    /// Debug: Print current state
    func debugPrintState() {
    }
}
#endif
