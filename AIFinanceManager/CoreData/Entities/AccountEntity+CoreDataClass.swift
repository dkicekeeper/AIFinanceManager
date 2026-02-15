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
        // Migrate from old logo field to iconSource
        let iconSource: IconSource?
        if let logoString = logo, let bankLogo = BankLogo(rawValue: logoString), bankLogo != .none {
            iconSource = .bankLogo(bankLogo)
        } else {
            iconSource = nil
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
            currency: currency ?? "KZT",
            iconSource: iconSource,
            depositInfo: depositInfo,
            createdDate: createdAt,
            shouldCalculateFromTransactions: shouldCalculateFromTransactions,  // ✨ Phase 10: Restore calculation mode
            initialBalance: balance
        )
    }

    /// Create from domain model
    nonisolated static func from(_ account: Account, context: NSManagedObjectContext) -> AccountEntity {
        let entity = AccountEntity(context: context)
        entity.id = account.id
        entity.name = account.name
        entity.balance = account.initialBalance ?? 0
        entity.currency = account.currency
        // Save iconSource as logo string (backward compatible)
        if case .bankLogo(let bankLogo) = account.iconSource {
            entity.logo = bankLogo.rawValue
        } else {
            entity.logo = BankLogo.none.rawValue
        }
        entity.isDeposit = account.isDeposit
        entity.bankName = account.depositInfo?.bankName
        entity.createdAt = account.createdDate ?? Date()
        entity.shouldCalculateFromTransactions = account.shouldCalculateFromTransactions  // ✨ Phase 10: Save calculation mode
        // Note: depositInfo details are not stored in AccountEntity
        // This would need to be extended if full deposit support is required
        return entity
    }
}
