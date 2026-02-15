//
//  RecurringSeriesEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias RecurringSeriesEntityCoreDataPropertiesSet = NSSet

extension RecurringSeriesEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringSeriesEntity> {
        return NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var currency: String?
    @NSManaged public var category: String?
    @NSManaged public var subcategory: String?
    @NSManaged public var descriptionText: String?
    @NSManaged public var frequency: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var lastGeneratedDate: Date?
    @NSManaged public var kind: String?
    @NSManaged public var brandLogo: String?
    @NSManaged public var brandId: String?
    @NSManaged public var status: String?
    @NSManaged public var account: AccountEntity?
    @NSManaged public var transactions: NSSet?
    @NSManaged public var occurrences: NSSet?

}

// MARK: Generated accessors for transactions
extension RecurringSeriesEntity {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for occurrences
extension RecurringSeriesEntity {

    @objc(addOccurrencesObject:)
    @NSManaged public func addToOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(removeOccurrencesObject:)
    @NSManaged public func removeFromOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(addOccurrences:)
    @NSManaged public func addToOccurrences(_ values: NSSet)

    @objc(removeOccurrences:)
    @NSManaged public func removeFromOccurrences(_ values: NSSet)

}

extension RecurringSeriesEntity : Identifiable {

}
