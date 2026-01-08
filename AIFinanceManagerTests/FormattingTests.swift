//
//  FormattingTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//

import Testing
@testable import AIFinanceManager

struct FormattingTests {
    
    @Test("Format currency with USD")
    func testFormatCurrencyUSD() {
        let result = Formatting.formatCurrency(1234.56, currency: "USD")
        #expect(result.contains("1,234.56") || result.contains("1234.56"))
        #expect(result.contains("$") || result.contains("USD"))
    }
    
    @Test("Format currency with EUR")
    func testFormatCurrencyEUR() {
        let result = Formatting.formatCurrency(999.99, currency: "EUR")
        #expect(result.contains("999.99") || result.contains("999,99"))
    }
    
    @Test("Format zero amount")
    func testFormatZero() {
        let result = Formatting.formatCurrency(0.0, currency: "USD")
        #expect(result.contains("0"))
    }
    
    @Test("Format large amount")
    func testFormatLargeAmount() {
        let result = Formatting.formatCurrency(1234567.89, currency: "USD")
        #expect(result.contains("1,234,567.89") || result.contains("1234567.89"))
    }
    
    @Test("Format negative amount")
    func testFormatNegative() {
        let result = Formatting.formatCurrency(-100.50, currency: "USD")
        #expect(result.contains("-") || result.contains("100.50"))
    }
}
