//
//  BalanceCalculationEngineTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 1
//
//  Unit tests for BalanceCalculationEngine
//

import Testing
import Foundation
@testable import AIFinanceManager

@Suite("BalanceCalculationEngine Tests")
struct BalanceCalculationEngineTests {

    // MARK: - Test Helpers

    private func createAccount(
        id: String = "acc-1",
        balance: Double = 1000.0,
        initialBalance: Double? = nil,
        currency: String = "USD"
    ) -> AccountBalance {
        return AccountBalance(
            accountId: id,
            currentBalance: balance,
            initialBalance: initialBalance,
            currency: currency
        )
    }

    private func createTransaction(
        id: String = "tx-1",
        type: TransactionType = .expense,
        amount: Double = 100.0,
        currency: String = "USD",
        accountId: String = "acc-1",
        date: String = "2026-01-15"
    ) -> Transaction {
        return Transaction(
            id: id,
            date: date,
            amount: amount,
            currency: currency,
            type: type,
            category: "Food",
            accountId: accountId,
            description: "Test transaction",
            recurring: nil,
            recurringSeriesId: nil
        )
    }

    // MARK: - Test Balance Calculation

    @Test("Calculate balance from initial balance - income")
    func testCalculateBalanceIncome() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(initialBalance: 1000.0)

        let transactions = [
            createTransaction(type: .income, amount: 500.0),
            createTransaction(id: "tx-2", type: .income, amount: 300.0)
        ]

        let balance = engine.calculateBalance(
            account: account,
            transactions: transactions,
            mode: .fromInitialBalance
        )

        // 1000 + 500 + 300 = 1800
        #expect(balance == 1800.0)
    }

    @Test("Calculate balance from initial balance - expense")
    func testCalculateBalanceExpense() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(initialBalance: 1000.0)

        let transactions = [
            createTransaction(type: .expense, amount: 200.0),
            createTransaction(id: "tx-2", type: .expense, amount: 150.0)
        ]

        let balance = engine.calculateBalance(
            account: account,
            transactions: transactions,
            mode: .fromInitialBalance
        )

        // 1000 - 200 - 150 = 650
        #expect(balance == 650.0)
    }

    @Test("Calculate balance from initial balance - mixed")
    func testCalculateBalanceMixed() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(initialBalance: 1000.0)

        let transactions = [
            createTransaction(id: "tx-1", type: .income, amount: 500.0),
            createTransaction(id: "tx-2", type: .expense, amount: 200.0),
            createTransaction(id: "tx-3", type: .income, amount: 300.0),
            createTransaction(id: "tx-4", type: .expense, amount: 100.0)
        ]

        let balance = engine.calculateBalance(
            account: account,
            transactions: transactions,
            mode: .fromInitialBalance
        )

        // 1000 + 500 - 200 + 300 - 100 = 1500
        #expect(balance == 1500.0)
    }

    @Test("Calculate balance - preserve imported mode")
    func testCalculateBalancePreserveImported() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1500.0)

        let transactions = [
            createTransaction(type: .income, amount: 500.0),
            createTransaction(id: "tx-2", type: .expense, amount: 200.0)
        ]

        let balance = engine.calculateBalance(
            account: account,
            transactions: transactions,
            mode: .preserveImported
        )

        // Should return current balance (transactions already included)
        #expect(balance == 1500.0)
    }

    // MARK: - Test Incremental Updates

    @Test("Apply income transaction")
    func testApplyIncomeTransaction() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1000.0)
        let transaction = createTransaction(type: .income, amount: 500.0)

        let newBalance = engine.applyTransaction(
            transaction,
            to: account.currentBalance,
            for: account
        )

        #expect(newBalance == 1500.0)
    }

    @Test("Apply expense transaction")
    func testApplyExpenseTransaction() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1000.0)
        let transaction = createTransaction(type: .expense, amount: 300.0)

        let newBalance = engine.applyTransaction(
            transaction,
            to: account.currentBalance,
            for: account
        )

        #expect(newBalance == 700.0)
    }

    @Test("Apply internal transfer - source")
    func testApplyInternalTransferSource() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1000.0)

        var transaction = createTransaction(type: .internalTransfer, amount: 200.0)
        transaction.convertedAmount = 200.0
        transaction.targetAccountId = "acc-2"

        let newBalance = engine.applyTransaction(
            transaction,
            to: account.currentBalance,
            for: account,
            isSource: true
        )

        // Source: 1000 - 200 = 800
        #expect(newBalance == 800.0)
    }

    @Test("Apply internal transfer - target")
    func testApplyInternalTransferTarget() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(id: "acc-2", balance: 500.0)

        var transaction = createTransaction(type: .internalTransfer, amount: 200.0, accountId: "acc-1")
        transaction.targetAccountId = "acc-2"
        transaction.targetAmount = 200.0

        let newBalance = engine.applyTransaction(
            transaction,
            to: account.currentBalance,
            for: account,
            isSource: false
        )

        // Target: 500 + 200 = 700
        #expect(newBalance == 700.0)
    }

    // MARK: - Test Revert Transaction

    @Test("Revert income transaction")
    func testRevertIncomeTransaction() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1500.0)
        let transaction = createTransaction(type: .income, amount: 500.0)

        let newBalance = engine.revertTransaction(
            transaction,
            from: account.currentBalance,
            for: account
        )

        // 1500 - 500 = 1000
        #expect(newBalance == 1000.0)
    }

    @Test("Revert expense transaction")
    func testRevertExpenseTransaction() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 700.0)
        let transaction = createTransaction(type: .expense, amount: 300.0)

        let newBalance = engine.revertTransaction(
            transaction,
            from: account.currentBalance,
            for: account
        )

        // 700 + 300 = 1000
        #expect(newBalance == 1000.0)
    }

    @Test("Revert internal transfer - source")
    func testRevertInternalTransferSource() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 800.0)

        var transaction = createTransaction(type: .internalTransfer, amount: 200.0)
        transaction.convertedAmount = 200.0
        transaction.targetAccountId = "acc-2"

        let newBalance = engine.revertTransaction(
            transaction,
            from: account.currentBalance,
            for: account,
            isSource: true
        )

        // Source revert: 800 + 200 = 1000
        #expect(newBalance == 1000.0)
    }

    // MARK: - Test Calculate Delta

    @Test("Calculate delta for add operation")
    func testCalculateDeltaAdd() async throws {
        let engine = BalanceCalculationEngine()

        let transaction = createTransaction(type: .income, amount: 500.0)

        let delta = engine.calculateDelta(
            for: .add(transaction),
            accountId: "acc-1",
            accountCurrency: "USD"
        )

        #expect(delta == 500.0)
    }

    @Test("Calculate delta for remove operation")
    func testCalculateDeltaRemove() async throws {
        let engine = BalanceCalculationEngine()

        let transaction = createTransaction(type: .income, amount: 500.0)

        let delta = engine.calculateDelta(
            for: .remove(transaction),
            accountId: "acc-1",
            accountCurrency: "USD"
        )

        #expect(delta == -500.0)
    }

    @Test("Calculate delta for update operation")
    func testCalculateDeltaUpdate() async throws {
        let engine = BalanceCalculationEngine()

        let oldTx = createTransaction(type: .income, amount: 300.0)
        let newTx = createTransaction(type: .income, amount: 500.0)

        let delta = engine.calculateDelta(
            for: .update(old: oldTx, new: newTx),
            accountId: "acc-1",
            accountCurrency: "USD"
        )

        // -300 + 500 = 200
        #expect(delta == 200.0)
    }

    // MARK: - Test Initial Balance Calculation

    @Test("Calculate initial balance")
    func testCalculateInitialBalance() async throws {
        let engine = BalanceCalculationEngine()

        let transactions = [
            createTransaction(id: "tx-1", type: .income, amount: 500.0),
            createTransaction(id: "tx-2", type: .expense, amount: 200.0)
        ]

        let initialBalance = engine.calculateInitialBalance(
            currentBalance: 1300.0,
            accountId: "acc-1",
            accountCurrency: "USD",
            transactions: transactions
        )

        // 1300 - (500 - 200) = 1000
        #expect(initialBalance == 1000.0)
    }

    // MARK: - Test Deposit Balance

    @Test("Calculate deposit balance - no capitalization")
    func testCalculateDepositBalanceNoCapitalization() async throws {
        let engine = BalanceCalculationEngine()

        let depositInfo = DepositInfo(
            principalBalance: 10000.0,
            annualRate: 5.0,
            capitalizationEnabled: false,
            interestAccruedNotCapitalized: 100.0,
            capitalizationDay: 1,
            lastInterestPostingMonth: nil,
            rateHistory: []
        )

        let balance = engine.calculateDepositBalance(depositInfo: depositInfo)

        // 10000 + 100 = 10100
        #expect(balance == 10100.0)
    }

    @Test("Calculate deposit balance - with capitalization")
    func testCalculateDepositBalanceWithCapitalization() async throws {
        let engine = BalanceCalculationEngine()

        let depositInfo = DepositInfo(
            principalBalance: 10000.0,
            annualRate: 5.0,
            capitalizationEnabled: true,
            interestAccruedNotCapitalized: 100.0,
            capitalizationDay: 1,
            lastInterestPostingMonth: nil,
            rateHistory: []
        )

        let balance = engine.calculateDepositBalance(depositInfo: depositInfo)

        // With capitalization: only principal (interest added to principal)
        #expect(balance == 10000.0)
    }

    @Test("Apply transaction to deposit - withdrawal")
    func testApplyTransactionToDepositWithdrawal() async throws {
        let engine = BalanceCalculationEngine()

        let depositInfo = DepositInfo(
            principalBalance: 10000.0,
            annualRate: 5.0,
            capitalizationEnabled: false,
            interestAccruedNotCapitalized: 500.0,
            capitalizationDay: 1,
            lastInterestPostingMonth: nil,
            rateHistory: []
        )

        let transaction = createTransaction(type: .internalTransfer, amount: 300.0)

        let result = engine.applyTransactionToDeposit(
            transaction,
            depositInfo: depositInfo,
            isSource: true
        )

        // Withdraw 300 from interest (500 - 300 = 200)
        #expect(result.depositInfo.interestAccruedNotCapitalized == 200.0)
        #expect(result.depositInfo.principalBalance == 10000.0)
        // Balance: 10000 + 200 = 10200
        #expect(result.balance == 10200.0)
    }

    @Test("Apply transaction to deposit - top up")
    func testApplyTransactionToDepositTopUp() async throws {
        let engine = BalanceCalculationEngine()

        let depositInfo = DepositInfo(
            principalBalance: 10000.0,
            annualRate: 5.0,
            capitalizationEnabled: true,
            interestAccruedNotCapitalized: 0,
            capitalizationDay: 1,
            lastInterestPostingMonth: nil,
            rateHistory: []
        )

        let transaction = createTransaction(type: .internalTransfer, amount: 2000.0)

        let result = engine.applyTransactionToDeposit(
            transaction,
            depositInfo: depositInfo,
            isSource: false
        )

        // Add 2000 to principal
        #expect(result.depositInfo.principalBalance == 12000.0)
        #expect(result.balance == 12000.0)
    }

    // MARK: - Test Currency Conversion

    @Test("Transaction with currency conversion")
    func testTransactionCurrencyConversion() async throws {
        let engine = BalanceCalculationEngine()

        let account = createAccount(balance: 1000.0, currency: "USD")

        var transaction = createTransaction(type: .income, amount: 500.0, currency: "EUR")
        transaction.convertedAmount = 550.0 // Converted to USD

        let newBalance = engine.applyTransaction(
            transaction,
            to: account.currentBalance,
            for: account
        )

        // Should use converted amount: 1000 + 550 = 1550
        #expect(newBalance == 1550.0)
    }
}
