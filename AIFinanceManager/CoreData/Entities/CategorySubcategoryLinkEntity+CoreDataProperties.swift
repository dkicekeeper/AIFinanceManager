//
//  CategorySubcategoryLinkEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData
public import Combine


public typealias CategorySubcategoryLinkEntityCoreDataPropertiesSet = NSSet

extension CategorySubcategoryLinkEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategorySubcategoryLinkEntity> {
        return NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var categoryId: String?
    @NSManaged public var subcategoryId: String?

}

extension CategorySubcategoryLinkEntity : Identifiable {

}
