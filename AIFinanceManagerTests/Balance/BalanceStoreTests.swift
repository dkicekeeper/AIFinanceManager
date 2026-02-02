//
//  BalanceStoreTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 1
//
//  Unit tests for BalanceStore
//

import Testing
import Foundation
@testable import AIFinanceManager

@Suite("BalanceStore Tests")
struct BalanceStoreTests {

    // MARK: - Test Account Registration

    @Test("Register single account")
    @MainActor
    func testRegisterAccount() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)

        #expect(store.getBalance(for: "acc-1") == 1000.0)
        #expect(store.getAccount("acc-1") != nil)
    }

    @Test("Register multiple accounts")
    @MainActor
    func testRegisterMultipleAccounts() async throws {
        let store = BalanceStore()

        let accounts = [
            AccountBalance(accountId: "acc-1", currentBalance: 1000.0, currency: "USD"),
            AccountBalance(accountId: "acc-2", currentBalance: 2000.0, currency: "EUR"),
            AccountBalance(accountId: "acc-3", currentBalance: 3000.0, currency: "KZT")
        ]

        store.registerAccounts(accounts)

        #expect(store.getBalance(for: "acc-1") == 1000.0)
        #expect(store.getBalance(for: "acc-2") == 2000.0)
        #expect(store.getBalance(for: "acc-3") == 3000.0)
        #expect(store.getAllAccounts().count == 3)
    }

    @Test("Remove account")
    @MainActor
    func testRemoveAccount() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)
        #expect(store.getBalance(for: "acc-1") == 1000.0)

        store.removeAccount("acc-1")
        #expect(store.getBalance(for: "acc-1") == nil)
        #expect(store.getAccount("acc-1") == nil)
    }

    // MARK: - Test Balance Operations

    @Test("Set balance for account")
    @MainActor
    func testSetBalance() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)
        store.setBalance(1500.0, for: "acc-1")

        #expect(store.getBalance(for: "acc-1") == 1500.0)
    }

    @Test("Update multiple balances")
    @MainActor
    func testUpdateBalances() async throws {
        let store = BalanceStore()

        let accounts = [
            AccountBalance(accountId: "acc-1", currentBalance: 1000.0, currency: "USD"),
            AccountBalance(accountId: "acc-2", currentBalance: 2000.0, currency: "EUR")
        ]

        store.registerAccounts(accounts)

        store.updateBalances([
            "acc-1": 1500.0,
            "acc-2": 2500.0
        ])

        #expect(store.getBalance(for: "acc-1") == 1500.0)
        #expect(store.getBalance(for: "acc-2") == 2500.0)
    }

    @Test("Batch update with custom logic")
    @MainActor
    func testBatchUpdate() async throws {
        let store = BalanceStore()

        let accounts = [
            AccountBalance(accountId: "acc-1", currentBalance: 1000.0, currency: "USD"),
            AccountBalance(accountId: "acc-2", currentBalance: 2000.0, currency: "EUR")
        ]

        store.registerAccounts(accounts)

        store.performBatchUpdate { accounts in
            var updates: [BalanceUpdate] = []

            for (id, var account) in accounts {
                account.currentBalance += 100.0
                accounts[id] = account

                updates.append(BalanceUpdate(
                    accountId: id,
                    newBalance: account.currentBalance,
                    source: .manual
                ))
            }

            return updates
        }

        #expect(store.getBalance(for: "acc-1") == 1100.0)
        #expect(store.getBalance(for: "acc-2") == 2100.0)
    }

    // MARK: - Test Calculation Mode

    @Test("Set and get calculation mode")
    @MainActor
    func testCalculationMode() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)

        // Default mode
        #expect(store.getCalculationMode(for: "acc-1") == .fromInitialBalance)

        // Set to imported
        store.setCalculationMode(.preserveImported, for: "acc-1")
        #expect(store.getCalculationMode(for: "acc-1") == .preserveImported)
        #expect(store.isImported("acc-1") == true)

        // Set back to manual
        store.markAsManual("acc-1")
        #expect(store.getCalculationMode(for: "acc-1") == .fromInitialBalance)
        #expect(store.isImported("acc-1") == false)
    }

    @Test("Mark as imported")
    @MainActor
    func testMarkAsImported() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)
        store.markAsImported("acc-1")

        #expect(store.isImported("acc-1") == true)
        #expect(store.getCalculationMode(for: "acc-1") == .preserveImported)
    }

    // MARK: - Test Initial Balance

    @Test("Set and get initial balance")
    @MainActor
    func testInitialBalance() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)

        #expect(store.getInitialBalance(for: "acc-1") == nil)

        store.setInitialBalance(500.0, for: "acc-1")
        #expect(store.getInitialBalance(for: "acc-1") == 500.0)
    }

    @Test("Clear initial balance")
    @MainActor
    func testClearInitialBalance() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            initialBalance: 500.0,
            currency: "USD"
        )

        store.registerAccount(account)
        #expect(store.getInitialBalance(for: "acc-1") == 500.0)

        store.clearInitialBalance(for: "acc-1")
        #expect(store.getInitialBalance(for: "acc-1") == nil)
    }

    // MARK: - Test Deposit Info

    @Test("Update deposit info")
    @MainActor
    func testUpdateDepositInfo() async throws {
        let store = BalanceStore()

        let depositInfo = DepositInfo(
            principalBalance: 10000.0,
            annualRate: 5.0,
            capitalizationEnabled: false,
            interestAccruedNotCapitalized: 100.0,
            capitalizationDay: 1,
            lastInterestPostingMonth: nil,
            rateHistory: []
        )

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 10100.0,
            depositInfo: depositInfo,
            currency: "USD",
            isDeposit: true
        )

        store.registerAccount(account)

        // Update deposit info
        var updatedInfo = depositInfo
        updatedInfo.principalBalance = 11000.0

        store.updateDepositInfo(updatedInfo, for: "acc-1")

        // Balance should be recalculated: 11000 + 100 = 11100
        #expect(store.getBalance(for: "acc-1") == 11100.0)
    }

    // MARK: - Test State Management

    @Test("Reset store")
    @MainActor
    func testReset() async throws {
        let store = BalanceStore()

        let accounts = [
            AccountBalance(accountId: "acc-1", currentBalance: 1000.0, currency: "USD"),
            AccountBalance(accountId: "acc-2", currentBalance: 2000.0, currency: "EUR")
        ]

        store.registerAccounts(accounts)
        #expect(store.getAllAccounts().count == 2)

        store.reset()
        #expect(store.getAllAccounts().count == 0)
        #expect(store.getBalance(for: "acc-1") == nil)
    }

    @Test("Snapshot and restore")
    @MainActor
    func testSnapshotRestore() async throws {
        let store = BalanceStore()

        let accounts = [
            AccountBalance(accountId: "acc-1", currentBalance: 1000.0, currency: "USD"),
            AccountBalance(accountId: "acc-2", currentBalance: 2000.0, currency: "EUR")
        ]

        store.registerAccounts(accounts)
        store.setInitialBalance(500.0, for: "acc-1")
        store.markAsImported("acc-2")

        // Take snapshot
        let snapshot = store.snapshot()

        // Modify store
        store.setBalance(9999.0, for: "acc-1")
        #expect(store.getBalance(for: "acc-1") == 9999.0)

        // Restore from snapshot
        store.restore(from: snapshot)
        #expect(store.getBalance(for: "acc-1") == 1000.0)
        #expect(store.getInitialBalance(for: "acc-1") == 500.0)
        #expect(store.isImported("acc-2") == true)
    }

    // MARK: - Test Published Property

    @Test("Published balances update")
    @MainActor
    func testPublishedBalances() async throws {
        let store = BalanceStore()

        let account = AccountBalance(
            accountId: "acc-1",
            currentBalance: 1000.0,
            currency: "USD"
        )

        store.registerAccount(account)

        // Check published property
        #expect(store.balances["acc-1"] == 1000.0)

        // Update balance
        store.setBalance(1500.0, for: "acc-1")
        #expect(store.balances["acc-1"] == 1500.0)
    }
}
