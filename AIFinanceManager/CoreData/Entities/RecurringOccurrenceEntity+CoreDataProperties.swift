//
//  RecurringOccurrenceEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created on 2026
//

import Foundation
import CoreData

extension RecurringOccurrenceEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringOccurrenceEntity> {
        return NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var seriesId: String?
    @NSManaged public var occurrenceDate: String?
    @NSManaged public var transactionId: String?
    @NSManaged public var series: RecurringSeriesEntity?

}

extension RecurringOccurrenceEntity : Identifiable {

}
