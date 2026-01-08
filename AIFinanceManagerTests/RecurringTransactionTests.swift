//
//  RecurringTransactionTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//

import Testing
import Foundation
@testable import AIFinanceManager

struct RecurringTransactionTests {
    
    @Test("RecurringFrequency has all cases")
    func testRecurringFrequencyCases() {
        let cases = RecurringFrequency.allCases
        #expect(cases.contains(.daily))
        #expect(cases.contains(.weekly))
        #expect(cases.contains(.monthly))
        #expect(cases.contains(.yearly))
    }
    
    @Test("RecurringFrequency display names")
    func testRecurringFrequencyDisplayNames() {
        #expect(RecurringFrequency.daily.displayName.count > 0)
        #expect(RecurringFrequency.weekly.displayName.count > 0)
        #expect(RecurringFrequency.monthly.displayName.count > 0)
        #expect(RecurringFrequency.yearly.displayName.count > 0)
    }
    
    @Test("RecurringSeries initializes correctly")
    func testRecurringSeriesInit() {
        let series = RecurringSeries(
            id: "test-id",
            amount: Decimal(100.0),
            currency: "USD",
            category: "Food",
            subcategory: nil,
            description: "Test",
            accountId: "account-1",
            targetAccountId: nil,
            frequency: .monthly,
            startDate: "2024-01-15",
            isActive: true
        )
        
        #expect(series.id == "test-id")
        #expect(series.amount == Decimal(100.0))
        #expect(series.currency == "USD")
        #expect(series.category == "Food")
        #expect(series.frequency == .monthly)
        #expect(series.isActive == true)
    }
    
    @Test("RecurringOccurrence initializes correctly")
    func testRecurringOccurrenceInit() {
        let occurrence = RecurringOccurrence(
            id: "occ-1",
            seriesId: "series-1",
            occurrenceDate: "2024-01-15",
            transactionId: "tx-1"
        )
        
        #expect(occurrence.id == "occ-1")
        #expect(occurrence.seriesId == "series-1")
        #expect(occurrence.occurrenceDate == "2024-01-15")
        #expect(occurrence.transactionId == "tx-1")
    }
}
