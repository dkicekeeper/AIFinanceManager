//
//  TransactionEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias TransactionEntityCoreDataPropertiesSet = NSSet

extension TransactionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionEntity> {
        return NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
    }

    @NSManaged public var amount: Double
    @NSManaged public var category: String?
    @NSManaged public var convertedAmount: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var currency: String?
    @NSManaged public var date: Date?
    @NSManaged public var descriptionText: String?
    @NSManaged public var id: String?
    @NSManaged public var subcategory: String?
    @NSManaged public var targetAmount: Double
    @NSManaged public var targetCurrency: String?
    @NSManaged public var type: String?
    @NSManaged public var accountName: String?
    @NSManaged public var targetAccountName: String?
    @NSManaged public var account: AccountEntity?
    @NSManaged public var recurringSeries: RecurringSeriesEntity?
    @NSManaged public var targetAccount: AccountEntity?

}

extension TransactionEntity : Identifiable {

}
