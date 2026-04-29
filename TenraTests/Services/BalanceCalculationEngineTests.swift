//
//  BalanceCalculationEngineTests.swift
//  TenraTests
//
//  Unit tests for BalanceCalculationEngine deposit gating.
//

import Testing
import Foundation
@testable import Tenra

@Suite("BalanceCalculationEngine deposit gating")
struct BalanceCalculationEngineTests {

    private let engine = BalanceCalculationEngine()

    private func depositAccountBalance(
        id: String = "d1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            depositInfo: DepositInfo(
                bankName: "T",
                principalBalance: Decimal(currentBalance),
                capitalizationEnabled: false,
                interestAccruedNotCapitalized: 0,
                interestRateAnnual: 0,
                interestRateHistory: [RateChange(effectiveFrom: "2020-01-01", annualRate: 0)],
                interestPostingDay: 1,
                lastInterestCalculationDate: "2020-01-01",
                lastInterestPostingMonth: "2020-01-01",
                interestAccruedForCurrentPeriod: 0,
                initialPrincipal: Decimal(currentBalance),
                startDate: "2020-01-01"
            ),
            currency: currency,
            isDeposit: true
        )
    }

    private func nonDepositAccountBalance(
        id: String = "a1",
        currency: String = "KZT",
        currentBalance: Double = 100_000
    ) -> AccountBalance {
        AccountBalance(
            accountId: id,
            currentBalance: currentBalance,
            initialBalance: currentBalance,
            currency: currency,
            isDeposit: false
        )
    }

    private func incomeTx(amount: Double, accountId: String) -> Transaction {
        Transaction(
            id: "i", date: "2026-01-01", description: "",
            amount: amount, currency: "KZT", convertedAmount: nil,
            type: .income, category: "Salary", subcategory: nil,
            accountId: accountId, targetAccountId: nil
        )
    }

    @Test("applyTransaction: .income on deposit is a no-op")
    func applyIncome_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("applyTransaction: .income on regular account adds amount")
    func applyIncome_onRegular_adds() {
        let acct = nonDepositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 125_000)
    }

    @Test("applyTransaction: .expense on deposit is a no-op")
    func applyExpense_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = Transaction(
            id: "e", date: "2026-01-01", description: "",
            amount: 10_000, currency: "KZT", convertedAmount: nil,
            type: .expense, category: "Other", subcategory: nil,
            accountId: acct.accountId, targetAccountId: nil
        )
        let new = engine.applyTransaction(tx, to: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("revertTransaction: .income on deposit is a no-op")
    func revertIncome_onDeposit_noop() {
        let acct = depositAccountBalance(currentBalance: 100_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.revertTransaction(tx, from: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }

    @Test("revertTransaction: .income on regular account subtracts amount")
    func revertIncome_onRegular_subtracts() {
        let acct = nonDepositAccountBalance(currentBalance: 125_000)
        let tx = incomeTx(amount: 25_000, accountId: acct.accountId)
        let new = engine.revertTransaction(tx, from: acct.currentBalance, for: acct)
        #expect(new == 100_000)
    }
}
