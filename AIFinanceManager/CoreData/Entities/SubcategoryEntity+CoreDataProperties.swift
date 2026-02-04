//
//  SubcategoryEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData
public import Combine


public typealias SubcategoryEntityCoreDataPropertiesSet = NSSet

extension SubcategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SubcategoryEntity> {
        return NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var name: String?
    @NSManaged public var iconName: String?
    @NSManaged public var transactions: NSSet?

}

// MARK: Generated accessors for transactions
extension SubcategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: SubcategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: SubcategoryEntity)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

extension SubcategoryEntity : Identifiable {

}
