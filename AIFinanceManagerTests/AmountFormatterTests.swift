//
//  AmountFormatterTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026
//

import Testing
@testable import AIFinanceManager

struct AmountFormatterTests {

    @Test("Parse valid decimal amount")
    func testParseValidAmount() {
        let result = AmountFormatter.parse("1234.56")
        #expect(result == 1234.56)
    }

    @Test("Parse amount with spaces")
    func testParseAmountWithSpaces() {
        let result = AmountFormatter.parse("1 234 567.89")
        #expect(result == 1234567.89)
    }

    @Test("Parse amount with comma as decimal separator")
    func testParseAmountWithComma() {
        let result = AmountFormatter.parse("1234,56")
        #expect(result == 1234.56)
    }

    @Test("Parse zero amount")
    func testParseZero() {
        let result = AmountFormatter.parse("0")
        #expect(result == 0)
    }

    @Test("Parse invalid amount returns nil")
    func testParseInvalidAmount() {
        let result = AmountFormatter.parse("abc")
        #expect(result == nil)
    }

    @Test("Format decimal for display")
    func testFormatDecimal() {
        let result = AmountFormatter.format(1234567.89)
        #expect(result == "1 234 567.89")
    }

    @Test("Validate valid input")
    func testValidateValidInput() {
        #expect(AmountFormatter.isValidInput("1234.56") == true)
        #expect(AmountFormatter.isValidInput("1 234.56") == true)
        #expect(AmountFormatter.isValidInput("1234,56") == true)
    }

    @Test("Validate invalid input")
    func testValidateInvalidInput() {
        #expect(AmountFormatter.isValidInput("abc") == false)
        #expect(AmountFormatter.isValidInput("12abc34") == false)
    }

    @Test("Validate decimal places")
    func testValidateDecimalPlaces() {
        #expect(AmountFormatter.validateDecimalPlaces("1234.56") == true)
        #expect(AmountFormatter.validateDecimalPlaces("1234.5") == true)
        #expect(AmountFormatter.validateDecimalPlaces("1234.567") == false)
        #expect(AmountFormatter.validateDecimalPlaces("1234") == true)
    }
}
