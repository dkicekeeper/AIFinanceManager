//
//  AccountEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias AccountEntityCoreDataClassSet = NSSet


public class AccountEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension AccountEntity {
    /// Convert to domain model
    func toAccount() -> Account {
        let bankLogo: BankLogo
        if let logoString = logo, let logo = BankLogo(rawValue: logoString) {
            bankLogo = logo
        } else {
            bankLogo = .none
        }
        
        // For now, depositInfo is nil because it's not stored in AccountEntity
        // This can be extended later if needed
        let depositInfo: DepositInfo? = nil
        if isDeposit {
            // Note: We don't have all DepositInfo fields in AccountEntity
            // This is a simplified conversion - full depositInfo would need additional fields
            // For now, we'll return nil and handle deposits separately if needed
        }
        
        return Account(
            id: id ?? "",
            name: name ?? "",
            balance: balance,
            currency: currency ?? "KZT",
            bankLogo: bankLogo,
            depositInfo: depositInfo,
            createdDate: createdAt
        )
    }
    
    /// Create from domain model
    static func from(_ account: Account, context: NSManagedObjectContext) -> AccountEntity {
        let entity = AccountEntity(context: context)
        entity.id = account.id
        entity.name = account.name
        entity.balance = account.balance
        entity.currency = account.currency
        entity.logo = account.bankLogo.rawValue
        entity.isDeposit = account.isDeposit
        entity.bankName = account.depositInfo?.bankName
        entity.createdAt = account.createdDate ?? Date()
        // Note: depositInfo details are not stored in AccountEntity
        // This would need to be extended if full deposit support is required
        return entity
    }
}
