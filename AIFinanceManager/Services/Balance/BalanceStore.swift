//
//  BalanceStore.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 1
//
//  SINGLE SOURCE OF TRUTH for account balances
//  Thread-safe state management with @MainActor
//

import Foundation
import Combine

// MARK: - Account Balance Model

/// Represents an account's balance state
struct AccountBalance: Equatable, Identifiable {
    let accountId: String
    var currentBalance: Double
    var initialBalance: Double?
    var depositInfo: DepositInfo?
    let currency: String
    let isDeposit: Bool

    var id: String { accountId }

    init(
        accountId: String,
        currentBalance: Double,
        initialBalance: Double? = nil,
        depositInfo: DepositInfo? = nil,
        currency: String,
        isDeposit: Bool = false
    ) {
        self.accountId = accountId
        self.currentBalance = currentBalance
        self.initialBalance = initialBalance
        self.depositInfo = depositInfo
        self.currency = currency
        self.isDeposit = isDeposit
    }

    /// Create AccountBalance from Account model
    static func from(_ account: Account) -> AccountBalance {
        return AccountBalance(
            accountId: account.id,
            currentBalance: account.balance,
            initialBalance: nil,
            depositInfo: account.depositInfo,
            currency: account.currency,
            isDeposit: account.isDeposit
        )
    }
}

// MARK: - Balance Calculation Mode

/// Determines how balance should be calculated for an account
/// NOTE: This is separate from BalanceCalculationService's version for new architecture
enum BalanceMode: Equatable {
    /// Manual accounts: balance = initialBalance + Σtransactions
    /// Used for accounts created manually with a specified initial balance
    case fromInitialBalance

    /// Imported accounts: transactions are already factored into current balance
    /// Used for accounts imported from CSV where balance already includes all transactions
    case preserveImported
}

// MARK: - Balance Update Operation

/// Represents a balance update operation
struct BalanceStoreUpdate: Equatable, Identifiable {
    let id: UUID
    let accountId: String
    let newBalance: Double
    let source: Source
    let timestamp: Date

    enum Source: Equatable {
        case transaction(String)      // Transaction ID
        case recalculation
        case csvImport
        case manual
        case deposit
    }

    init(
        accountId: String,
        newBalance: Double,
        source: Source,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.newBalance = newBalance
        self.source = source
        self.timestamp = timestamp
    }
}

// MARK: - Balance Store

/// Thread-safe store for account balances
/// SINGLE SOURCE OF TRUTH - all balance data flows through this store
@MainActor
final class BalanceStore: ObservableObject {

    // MARK: - Published State

    /// Current balances for all accounts
    /// UI components observe this for real-time updates
    @Published private(set) var balances: [String: Double] = [:]

    // MARK: - Private State

    /// Detailed account balance information
    private var accounts: [String: AccountBalance] = [:]

    /// Calculation mode for each account
    private var calculationModes: [String: BalanceMode] = [:]

    /// History of balance updates (for debugging/auditing)
    private var updateHistory: [BalanceStoreUpdate] = []
    private let maxHistorySize: Int = 100

    // MARK: - Initialization

    init() {
        #if DEBUG
        print("✅ BalanceStore initialized")
        #endif
    }

    // MARK: - Account Management

    /// Register an account in the store
    func registerAccount(_ account: AccountBalance) {
        accounts[account.accountId] = account
        balances[account.accountId] = account.currentBalance

        #if DEBUG
        print("📝 Registered account: \(account.accountId), balance: \(account.currentBalance)")
        #endif
    }

    /// Register multiple accounts
    func registerAccounts(_ accountList: [AccountBalance]) {
        for account in accountList {
            accounts[account.accountId] = account
            balances[account.accountId] = account.currentBalance
        }

        #if DEBUG
        print("📝 Registered \(accountList.count) accounts")
        #endif
    }

    /// Remove account from store
    func removeAccount(_ accountId: String) {
        accounts.removeValue(forKey: accountId)
        balances.removeValue(forKey: accountId)
        calculationModes.removeValue(forKey: accountId)

        #if DEBUG
        print("🗑️ Removed account: \(accountId)")
        #endif
    }

    /// Get account details
    func getAccount(_ accountId: String) -> AccountBalance? {
        return accounts[accountId]
    }

    /// Get all accounts
    func getAllAccounts() -> [AccountBalance] {
        return Array(accounts.values)
    }

    // MARK: - Balance Operations

    /// Set balance for a specific account
    func setBalance(
        _ balance: Double,
        for accountId: String,
        source: BalanceStoreUpdate.Source = .manual
    ) {
        guard var account = accounts[accountId] else {
            #if DEBUG
            print("⚠️ Cannot set balance - account not found: \(accountId)")
            #endif
            return
        }

        account.currentBalance = balance
        accounts[accountId] = account
        balances[accountId] = balance

        recordUpdate(BalanceStoreUpdate(
            accountId: accountId,
            newBalance: balance,
            source: source
        ))

        #if DEBUG
        print("💰 Updated balance for \(accountId): \(balance)")
        #endif
    }

    /// Get current balance for account
    func getBalance(for accountId: String) -> Double? {
        return balances[accountId]
    }

    /// Update multiple balances atomically
    func updateBalances(
        _ updates: [String: Double],
        source: BalanceStoreUpdate.Source = .recalculation
    ) {
        var updatedCount = 0

        for (accountId, newBalance) in updates {
            guard var account = accounts[accountId] else { continue }

            account.currentBalance = newBalance
            accounts[accountId] = account
            balances[accountId] = newBalance

            recordUpdate(BalanceStoreUpdate(
                accountId: accountId,
                newBalance: newBalance,
                source: source
            ))

            updatedCount += 1
        }

        #if DEBUG
        print("💰 Batch updated \(updatedCount) balances")
        #endif
    }

    /// Perform atomic batch update with custom logic
    func performBatchUpdate(_ block: (inout [String: AccountBalance]) -> [BalanceStoreUpdate]) {
        let updates = block(&accounts)

        // Apply updates to published balances
        for update in updates {
            balances[update.accountId] = update.newBalance
            recordUpdate(update)
        }

        #if DEBUG
        print("💰 Performed batch update with \(updates.count) changes")
        #endif
    }

    // MARK: - Calculation Mode Management

    /// Set calculation mode for account
    func setCalculationMode(_ mode: BalanceMode, for accountId: String) {
        calculationModes[accountId] = mode

        #if DEBUG
        print("⚙️ Set calculation mode for \(accountId): \(mode)")
        #endif
    }

    /// Get calculation mode for account
    func getCalculationMode(for accountId: String) -> BalanceMode {
        return calculationModes[accountId] ?? .fromInitialBalance
    }

    /// Mark account as imported (transactions already in balance)
    func markAsImported(_ accountId: String) {
        setCalculationMode(.preserveImported, for: accountId)
    }

    /// Mark account as manual (transactions need to be applied)
    func markAsManual(_ accountId: String) {
        setCalculationMode(.fromInitialBalance, for: accountId)
    }

    /// Check if account is imported
    func isImported(_ accountId: String) -> Bool {
        return getCalculationMode(for: accountId) == .preserveImported
    }

    // MARK: - Initial Balance Management

    /// Set initial balance for account
    func setInitialBalance(_ balance: Double, for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.initialBalance = balance
        accounts[accountId] = account

        #if DEBUG
        print("🏦 Set initial balance for \(accountId): \(balance)")
        #endif
    }

    /// Get initial balance for account
    func getInitialBalance(for accountId: String) -> Double? {
        let balance = accounts[accountId]?.initialBalance

        #if DEBUG
        print("🔍 [BalanceStore] getInitialBalance for \(accountId):")
        print("   Account exists: \(accounts[accountId] != nil)")
        print("   InitialBalance: \(balance?.description ?? "nil")")
        print("   Mode: \(calculationModes[accountId] ?? .fromInitialBalance)")
        #endif

        return balance
    }

    /// Clear initial balance for account
    func clearInitialBalance(for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.initialBalance = nil
        accounts[accountId] = account

        #if DEBUG
        print("🗑️ Cleared initial balance for \(accountId)")
        #endif
    }

    // MARK: - Deposit Info Management

    /// Update deposit info for account
    func updateDepositInfo(_ depositInfo: DepositInfo, for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.depositInfo = depositInfo
        accounts[accountId] = account

        // Recalculate deposit balance
        var totalBalance: Decimal = depositInfo.principalBalance
        if !depositInfo.capitalizationEnabled {
            totalBalance += depositInfo.interestAccruedNotCapitalized
        }

        let newBalance = NSDecimalNumber(decimal: totalBalance).doubleValue
        balances[accountId] = newBalance

        recordUpdate(BalanceStoreUpdate(
            accountId: accountId,
            newBalance: newBalance,
            source: .deposit
        ))

        #if DEBUG
        print("🏦 Updated deposit info for \(accountId), new balance: \(newBalance)")
        #endif
    }

    // MARK: - State Management

    /// Clear all data
    func reset() {
        accounts.removeAll()
        balances.removeAll()
        calculationModes.removeAll()
        updateHistory.removeAll()

        #if DEBUG
        print("🔄 BalanceStore reset")
        #endif
    }

    /// Get current state snapshot
    func snapshot() -> BalanceStoreSnapshot {
        return BalanceStoreSnapshot(
            accounts: accounts,
            balances: balances,
            calculationModes: calculationModes,
            updateHistory: updateHistory
        )
    }

    /// Restore from snapshot
    func restore(from snapshot: BalanceStoreSnapshot) {
        accounts = snapshot.accounts
        balances = snapshot.balances
        calculationModes = snapshot.calculationModes
        updateHistory = snapshot.updateHistory

        #if DEBUG
        print("🔄 BalanceStore restored from snapshot")
        #endif
    }

    // MARK: - Private Helpers

    /// Record update in history
    private func recordUpdate(_ update: BalanceStoreUpdate) {
        updateHistory.append(update)

        // Maintain max history size
        if updateHistory.count > maxHistorySize {
            updateHistory.removeFirst(updateHistory.count - maxHistorySize)
        }
    }
}

// MARK: - Balance Store Snapshot

/// Snapshot of BalanceStore state (for backup/restore)
struct BalanceStoreSnapshot {
    let accounts: [String: AccountBalance]
    let balances: [String: Double]
    let calculationModes: [String: BalanceMode]
    let updateHistory: [BalanceStoreUpdate]
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceStore {
    /// Print current state for debugging
    func debugPrintState() {
        print("====== BalanceStore State ======")
        print("Accounts: \(accounts.count)")
        print("Balances: \(balances.count)")
        print("Calculation Modes: \(calculationModes.count)")
        print("Update History: \(updateHistory.count)")
        print("================================")

        for (accountId, balance) in balances.sorted(by: { $0.key < $1.key }) {
            let mode = calculationModes[accountId] ?? .fromInitialBalance
            let initial = accounts[accountId]?.initialBalance ?? 0
            print("  \(accountId): \(balance) (mode: \(mode), initial: \(initial))")
        }
    }

    /// Get update history for account
    func getUpdateHistory(for accountId: String) -> [BalanceStoreUpdate] {
        return updateHistory.filter { $0.accountId == accountId }
    }
}
#endif
