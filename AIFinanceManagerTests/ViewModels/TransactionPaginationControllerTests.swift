//
//  TransactionPaginationControllerTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026-02-23
//  Task 9: Unit tests for TransactionPaginationController supporting types
//

import Testing
@testable import AIFinanceManager

// MARK: - TransactionSection Tests

@MainActor
struct TransactionPaginationControllerTests {

    @Test("TransactionSection has correct id and date from init")
    func testTransactionSectionInit() {
        let section = TransactionSection(date: "2026-02-23", transactions: [])
        #expect(section.id == "2026-02-23")
        #expect(section.date == "2026-02-23")
        #expect(section.transactions.isEmpty)
    }

    @Test("TransactionSection stores provided transactions")
    func testTransactionSectionStoresTransactions() {
        let tx = Transaction(
            id: "tx-1",
            date: "2026-02-23",
            description: "Coffee",
            amount: 500,
            currency: "KZT",
            type: .expense,
            category: "Food"
        )
        let section = TransactionSection(date: "2026-02-23", transactions: [tx])
        #expect(section.transactions.count == 1)
        #expect(section.transactions.first?.id == "tx-1")
    }

    @Test("TransactionSection id equals date string")
    func testTransactionSectionIdEqualsDate() {
        let date = "2025-12-31"
        let section = TransactionSection(date: date, transactions: [])
        #expect(section.id == section.date)
    }
}

// MARK: - TransactionSectionKeyFormatter Tests

struct TransactionSectionKeyFormatterTests {

    @Test("Formatter returns YYYY-MM-DD for a known date")
    func testSectionKeyFormatterKnownDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 23
        let date = Calendar.current.date(from: components)!
        let key = TransactionSectionKeyFormatter.string(from: date)
        #expect(key == "2026-02-23")
    }

    @Test("Formatter zero-pads month and day")
    func testSectionKeyFormatterZeroPadding() {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 5
        let date = Calendar.current.date(from: components)!
        let key = TransactionSectionKeyFormatter.string(from: date)
        #expect(key == "2025-01-05")
    }

    @Test("Formatter returns consistent results for same date")
    func testSectionKeyFormatterConsistency() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        let date = Calendar.current.date(from: components)!
        let key1 = TransactionSectionKeyFormatter.string(from: date)
        let key2 = TransactionSectionKeyFormatter.string(from: date)
        #expect(key1 == key2)
    }
}
