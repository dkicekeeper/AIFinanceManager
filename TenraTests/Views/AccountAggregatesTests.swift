//
//  AccountAggregatesTests.swift
//  TenraTests
//
//  Unit tests for AccountAggregatesCalculator.
//

import XCTest
@testable import Tenra

final class AccountAggregatesTests: XCTestCase {
    func test_emptyTransactions_returnsZeros() {
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: []
        )
        XCTAssertEqual(result.totalTransactions, 0)
        XCTAssertEqual(result.totalIncome, 0)
        XCTAssertEqual(result.totalExpense, 0)
    }

    func test_incomeAndExpenseOnSameCurrency_sumsCorrectly() {
        let txs: [Transaction] = [
            makeTx(type: .income, amount: 1000, accountId: "a1", currency: "USD"),
            makeTx(type: .expense, amount: 200, accountId: "a1", currency: "USD"),
            makeTx(type: .expense, amount: 50, accountId: "a1", currency: "USD"),
        ]
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(result.totalTransactions, 3)
        XCTAssertEqual(result.totalIncome, 1000, accuracy: 0.001)
        XCTAssertEqual(result.totalExpense, 250, accuracy: 0.001)
    }

    func test_transferReflectsFromSourceAndTargetPerspective() {
        let txs: [Transaction] = [
            makeTx(
                type: .internalTransfer,
                amount: 500,
                accountId: "a1",
                targetAccountId: "a2",
                currency: "USD"
            ),
        ]
        let r1 = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(r1.totalExpense, 500, accuracy: 0.001)
        XCTAssertEqual(r1.totalIncome, 0, accuracy: 0.001)

        let r2 = AccountAggregatesCalculator.compute(
            accountId: "a2",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(r2.totalIncome, 500, accuracy: 0.001)
        XCTAssertEqual(r2.totalExpense, 0, accuracy: 0.001)
    }

    func test_unrelatedAccountIsIgnored() {
        let txs: [Transaction] = [
            makeTx(type: .income, amount: 9999, accountId: "b1", currency: "USD"),
            makeTx(type: .expense, amount: 1234, accountId: "b1", currency: "USD"),
        ]
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(result.totalTransactions, 0)
        XCTAssertEqual(result.totalIncome, 0)
        XCTAssertEqual(result.totalExpense, 0)
    }

    func test_loanPaymentFromAccount_isExpense() {
        let txs: [Transaction] = [
            makeTx(
                type: .loanPayment,
                amount: 250,
                accountId: "a1",
                targetAccountId: "loan1",
                currency: "USD"
            ),
        ]
        let result = AccountAggregatesCalculator.compute(
            accountId: "a1",
            accountCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(result.totalTransactions, 1)
        XCTAssertEqual(result.totalExpense, 250, accuracy: 0.001)
        XCTAssertEqual(result.totalIncome, 0, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeTx(
        type: TransactionType,
        amount: Double,
        accountId: String?,
        targetAccountId: String? = nil,
        currency: String
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: "2026-04-23",
            description: "test",
            amount: amount,
            currency: currency,
            type: type,
            category: "Test",
            accountId: accountId,
            targetAccountId: targetAccountId
        )
    }
}
