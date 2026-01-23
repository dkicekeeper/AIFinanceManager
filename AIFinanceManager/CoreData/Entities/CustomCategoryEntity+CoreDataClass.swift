//
//  CustomCategoryEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias CustomCategoryEntityCoreDataClassSet = NSSet


public class CustomCategoryEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension CustomCategoryEntity {
    /// Convert to domain model
    func toCustomCategory() -> CustomCategory {
        let transactionType = TransactionType(rawValue: type ?? "expense") ?? .expense
        
        return CustomCategory(
            id: id ?? UUID().uuidString,
            name: name ?? "",
            iconName: iconName,
            colorHex: colorHex ?? "#000000",
            type: transactionType,
            budgetAmount: nil, // Not stored in Entity yet
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
    }
    
    /// Create from domain model
    static func from(_ category: CustomCategory, context: NSManagedObjectContext) -> CustomCategoryEntity {
        let entity = CustomCategoryEntity(context: context)
        entity.id = category.id
        entity.name = category.name
        entity.type = category.type.rawValue
        entity.iconName = category.iconName
        entity.colorHex = category.colorHex
        // Note: budget fields are not stored in Entity yet
        return entity
    }
}
