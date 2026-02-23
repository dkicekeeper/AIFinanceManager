//
//  TransactionEntity+SectionKey.swift
//  AIFinanceManager
//
//  Created on 2026-02-23
//  Task 9: NSFetchedResultsController section grouping support
//

import CoreData

extension TransactionEntity {
    /// Transient computed property for NSFetchedResultsController section grouping.
    /// Returns "YYYY-MM-DD" string for the transaction's date.
    @objc var dateSectionKey: String {
        guard let date = self.date else { return "0000-00-00" }
        return TransactionSectionKeyFormatter.string(from: date)
    }
}

/// Dedicated formatter to avoid repeated DateFormatter allocation.
/// Using an enum with a static formatter ensures a single shared instance
/// across all TransactionEntity objects.
enum TransactionSectionKeyFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
