//
//  CustomCategoryEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias CustomCategoryEntityCoreDataPropertiesSet = NSSet

extension CustomCategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CustomCategoryEntity> {
        return NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var name: String?
    @NSManaged public var type: String?
    @NSManaged public var iconName: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var budgetAmount: Double
    @NSManaged public var budgetPeriod: String?
    @NSManaged public var budgetStartDate: Date?
    @NSManaged public var budgetResetDay: Int64
    @NSManaged public var transactions: NSSet?

    // MARK: - Phase 22: Budget Spending Cache
    /// Cached total spent in the current budget period (base currency).
    /// Invalidated whenever a transaction in this category changes.
    @NSManaged public var cachedSpentAmount: Double
    @NSManaged public var cachedSpentUpdatedAt: Date?
    @NSManaged public var cachedSpentCurrency: String?

}

// MARK: Generated accessors for transactions
extension CustomCategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: CustomCategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: CustomCategoryEntity)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

extension CustomCategoryEntity : Identifiable {

}
