//
//  RecurringSeriesEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData
public import Combine

public typealias RecurringSeriesEntityCoreDataClassSet = NSSet


public class RecurringSeriesEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension RecurringSeriesEntity {
    /// Convert to domain model
    func toRecurringSeries() -> RecurringSeries {
        let frequency = RecurringFrequency(rawValue: self.frequency ?? "monthly") ?? .monthly
        let kind = RecurringSeriesKind(rawValue: self.kind ?? "generic") ?? .generic
        let brandLogo = self.brandLogo.flatMap { BankLogo(rawValue: $0) }
        let status = self.status.flatMap { SubscriptionStatus(rawValue: $0) }
        
        return RecurringSeries(
            id: id ?? UUID().uuidString,
            isActive: isActive,
            amount: amount as? Decimal ?? 0,
            currency: currency ?? "KZT",
            category: category ?? "",
            subcategory: subcategory,
            description: descriptionText ?? "",
            accountId: account?.id,
            targetAccountId: nil, // Not stored in Entity yet
            frequency: frequency,
            startDate: startDate.map { DateFormatters.dateFormatter.string(from: $0) } ?? "",
            lastGeneratedDate: lastGeneratedDate.map { DateFormatters.dateFormatter.string(from: $0) },
            kind: kind,
            brandLogo: brandLogo,
            brandId: brandId,
            reminderOffsets: nil, // Not stored in Entity yet
            status: status
        )
    }
    
    /// Create from domain model
    static func from(_ series: RecurringSeries, context: NSManagedObjectContext) -> RecurringSeriesEntity {
        let entity = RecurringSeriesEntity(context: context)
        entity.id = series.id
        entity.isActive = series.isActive
        entity.amount = NSDecimalNumber(decimal: series.amount)
        entity.currency = series.currency
        entity.category = series.category
        entity.subcategory = series.subcategory
        entity.descriptionText = series.description
        entity.frequency = series.frequency.rawValue
        entity.startDate = DateFormatters.dateFormatter.date(from: series.startDate)
        entity.lastGeneratedDate = series.lastGeneratedDate.flatMap { DateFormatters.dateFormatter.date(from: $0) }
        entity.kind = series.kind.rawValue
        entity.brandLogo = series.brandLogo?.rawValue
        entity.brandId = series.brandId
        entity.status = series.status?.rawValue
        // account relationship will be set separately
        return entity
    }
}
