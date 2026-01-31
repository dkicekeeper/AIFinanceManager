//
//  CategoryAggregateEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created on 2026
//
//

public import Foundation
public import CoreData


extension CategoryAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryAggregateEntity> {
        return NSFetchRequest<CategoryAggregateEntity>(entityName: "CategoryAggregateEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var categoryName: String?
    @NSManaged public var subcategoryName: String?
    @NSManaged public var year: Int16
    @NSManaged public var month: Int16
    @NSManaged public var totalAmount: Double
    @NSManaged public var transactionCount: Int32
    @NSManaged public var currency: String?
    @NSManaged public var lastUpdated: Date?
    @NSManaged public var lastTransactionDate: Date?
}

extension CategoryAggregateEntity : Identifiable {

}
