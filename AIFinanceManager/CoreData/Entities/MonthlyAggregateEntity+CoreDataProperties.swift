//
//  MonthlyAggregateEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Phase 22: Properties for MonthlyAggregateEntity.
//

public import Foundation
public import CoreData

extension MonthlyAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MonthlyAggregateEntity> {
        return NSFetchRequest<MonthlyAggregateEntity>(entityName: "MonthlyAggregateEntity")
    }

    /// Unique key: "monthly_{year}_{month}_{currency}"
    @NSManaged public var id: String?
    @NSManaged public var year: Int16
    @NSManaged public var month: Int16
    @NSManaged public var currency: String?
    @NSManaged public var totalIncome: Double
    @NSManaged public var totalExpenses: Double
    @NSManaged public var netFlow: Double
    @NSManaged public var transactionCount: Int32
    @NSManaged public var lastUpdated: Date?
}

extension MonthlyAggregateEntity: Identifiable {

}
